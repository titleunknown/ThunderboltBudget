import Foundation
import AppKit
import IOKit
import IOKit.usb
import Combine
import SwiftUI
import UserNotifications

private func usbCallback(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) -> Void {
    while IOIteratorNext(iterator) != 0 {}
    HardwareWatcher.shared.triggerUpdate()
}

private func displayCallback(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutableRawPointer?) -> Void {
    HardwareWatcher.shared.triggerUpdate()
}

class HardwareWatcher {
    static let shared = HardwareWatcher()
    
    var onHardwareChanged: (() -> Void)?
    
    private var notifyPort: IONotificationPortRef?
    private var debounceTimer: Timer?
    
    private var usbAddedIter: io_iterator_t = 0
    private var usbRemovedIter: io_iterator_t = 0
    
    func startMonitoring() {
        if notifyPort != nil { return } // Reject duplicate starts
        
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notifyPort else { return }
        
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        
        CGDisplayRegisterReconfigurationCallback(displayCallback, nil)
        
        let match1 = IOServiceMatching("IOUSBDevice") as CFDictionary
        IOServiceAddMatchingNotification(port, kIOPublishNotification, match1, usbCallback, nil, &usbAddedIter)
        while IOIteratorNext(usbAddedIter) != 0 {} 
        
        let match2 = IOServiceMatching("IOUSBDevice") as CFDictionary
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, match2, usbCallback, nil, &usbRemovedIter)
        while IOIteratorNext(usbRemovedIter) != 0 {} 
    }
    
    func triggerUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.debounceTimer?.invalidate()
            self?.debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                self?.onHardwareChanged?()
            }
        }
    }
}

class LiveAnalytics: ObservableObject {
    static let shared = LiveAnalytics()
    
    @Published var totalTrafficGbps: [Double] = Array(repeating: 0.0, count: 60)
    
    private var timer: Timer?
    
    // Track previous cumulative totals to calculate deltas
    private var lastExternalDiskMB: Double = 0
    private var lastExternalNetBytes: Double = 0
    private var lastStaticDisplayGbps: Double = 0
    
    // We only begin calculating differences after the first tick finishes storing state
    private var isFirstTick = true
    
    func start() {
        if timer != nil { return }
        
        // Request Notification Permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted { print("Notifications authorized") }
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollMetrics()
        }
        // Force immediate first tick
        pollMetrics()
    }
    
    private func pollMetrics() {
        Task {
            let diskMB = await fetchExternalDiskCumulativeMB()
            let netBytes = await fetchExternalNetworkCumulativeBytes()
            let displayGbps = await fetchStaticDisplayGbps() // Already calculated in HardwareManager
            
            await MainActor.run {
                if isFirstTick {
                    isFirstTick = false
                } else {
                    // Calculate deltas over the 1-second interval
                    let diskDeltaMB = max(0, diskMB - lastExternalDiskMB)
                    let netDeltaBytes = max(0, netBytes - lastExternalNetBytes)
                    
                    // Convert everything to Gbps
                    let diskGbps = (diskDeltaMB * 8) / 1000.0
                    let netGbps = (netDeltaBytes * 8) / 1_000_000_000.0
                    
                    let newTotal = diskGbps + netGbps + displayGbps
                    
                    totalTrafficGbps.append(newTotal)
                    if totalTrafficGbps.count > 60 {
                        totalTrafficGbps.removeFirst()
                    }
                    
                    if newTotal >= 36.0 {
                        self.triggerBottleneckWarning(consumption: newTotal)
                    }
                }
                
                lastExternalDiskMB = diskMB
                lastExternalNetBytes = netBytes
                lastStaticDisplayGbps = displayGbps
            }
        }
    }
    
    private var lastNotificationTime = Date().addingTimeInterval(-60) // Prevent spamming
    
    private func triggerBottleneckWarning(consumption: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastNotificationTime) > 60 else { return } // Cooldown 1 minute
        lastNotificationTime = now
        
        let content = UNMutableNotificationContent()
        content.title = "Bandwidth Bottleneck Detected"
        content.body = String(format: "Your Thunderbolt bus is currently pushing %.1f Gbps. Consider moving a high-bandwidth device to a separate physical port cluster on your Mac for optimal performance.", consumption)
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func fetchExternalDiskCumulativeMB() async -> Double {
        let output = await runShell("iostat -I")
        var sum = 0.0
        
        let lines = output.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return 0.0 }
        
        // Find columns dynamically
        let headers = lines[0].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let stats = lines[2].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        for (idx, disk) in headers.enumerated() {
            if disk == "disk0" { continue } // Ignore internal NVMe
            
            // iostat pairs stats in blocks of 3: KB/t, xfrs, MB
            let mbIndex = (idx * 3) + 2
            if mbIndex < stats.count {
                if let val = Double(stats[mbIndex]) {
                    sum += val
                }
            }
        }
        return sum
    }
    
    private func fetchExternalNetworkCumulativeBytes() async -> Double {
        let output = await runShell("netstat -ib")
        var sum = 0.0
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let cols = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard cols.count > 10 else { continue }
            
            let name = cols[0]
            // We want external physical adapters (usually enX where X is not 0 (Wi-Fi)).
            // Ignore loopback (lo0), awdl, llw, bridge, utun
            if name == "en0" || name.hasPrefix("lo") || name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("bridge") || name.hasPrefix("utun") {
                continue
            }
            
            // On netstat -ib, standard output usually has Ibytes at col 6 or 7, and Obytes at col 9 or 10.
            if let ibytes = Double(cols[6]), let obytes = Double(cols[9]) {
                sum += (ibytes + obytes)
            }
        }
        
        return sum
    }
    
    @MainActor
    private func fetchStaticDisplayGbps() -> Double {
        // Find displays in the tree and sum their mathematically hardcoded link bandwidth
        return HardwareManager.shared.gatherSystemTotal() 
    }
    
    private func runShell(_ command: String) async -> String {
        return await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return ""
            }
        }.value
    }
}
