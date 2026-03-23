import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
class HardwareManager: ObservableObject {
    static let shared = HardwareManager()

    @Published var deviceTrees: [DeviceNode] = []
    @Published var expandedNodes: Set<UUID> = []
    @Published var isScanning = false

    private var liveUpdateTimer: Timer?

    init() {
        HardwareWatcher.shared.onHardwareChanged = { [weak self] in
            Task { @MainActor in
                self?.performScan()
            }
        }
        HardwareWatcher.shared.startMonitoring()
        LiveAnalytics.shared.start()
        performScan()

        // Update port labels and total every second from live data
        liveUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.applyLiveBandwidth()
            }
        }
    }

    func performScan() {
        guard !isScanning else { return }
        isScanning = true

        Task {
            let (scannedTrees, allIDs) = await Task.detached(priority: .userInitiated) {
                let scanner = HardwareScanner()
                let trees = scanner.scanForDevices()
                let ids = UIBackgroundWorkers.gatherAllDeviceIDs(from: trees)
                return (trees, ids)
            }.value

            self.deviceTrees = scannedTrees
            self.expandedNodes = allIDs
            self.isScanning = false
        }
    }

    /// Updates the Left Back Port (where the TB storage device is) with live iostat data.
    /// Distributes total external disk+net throughput across active TB ports.
    func applyLiveBandwidth() {
        guard !deviceTrees.isEmpty else { return }
        guard let busIdx = deviceTrees.firstIndex(where: { $0.name == "Thunderbolt Bus" }),
              var ports = deviceTrees[busIdx].children else { return }

        let liveGbps = LiveAnalytics.shared.totalTrafficGbps.last ?? 0.0

        // Find which ports have devices connected
        let activePorts = ports.indices.filter { ports[$0].children != nil && !(ports[$0].children!.isEmpty) }
        let portCount = max(activePorts.count, 1)

        // Distribute live bandwidth evenly across active ports
        var updatedPorts: [DeviceNode] = []
        for (i, port) in ports.enumerated() {
            let maxCap = 40.0
            let usedGbps = activePorts.contains(i) ? liveGbps / Double(portCount) : 0.0
            let ratio = min(usedGbps / maxCap, 1.0)
            let newLabel = String(format: "%.1f / %.0f Gb/s", usedGbps, maxCap)
            updatedPorts.append(DeviceNode(
                id: port.id,
                name: port.name,
                iconName: port.iconName,
                bandwidthLabel: newLabel,
                uid: port.uid,
                children: port.children,
                bandwidthRatio: ratio
            ))
        }

        var updatedTrees = deviceTrees
        var updatedBus = deviceTrees[busIdx]
        updatedBus.children = updatedPorts
        updatedTrees[busIdx] = updatedBus
        deviceTrees = updatedTrees
    }

    func gatherSystemTotal() -> Double {
        return LiveAnalytics.shared.totalTrafficGbps.last ?? 0.0
    }

    func copyMarkdownAction() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let text = UIBackgroundWorkers.generateHardwareMarkdown(from: deviceTrees)
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Thread-Safe Pure Functions
struct UIBackgroundWorkers {

    static func generateHardwareMarkdown(from nodes: [DeviceNode], depth: Int = 0) -> String {
        var result = ""
        let indent = String(repeating: "  ", count: depth)
        for node in nodes {
            let bwSuffix = node.bandwidthLabel != nil ? " [\(node.bandwidthLabel!)]" : ""
            result += "\(indent)- \(node.name)\(bwSuffix)\n"
            if let children = node.children {
                result += generateHardwareMarkdown(from: children, depth: depth + 1)
            }
        }
        return result
    }

    static func gatherAllDeviceIDs(from nodes: [DeviceNode]) -> Set<UUID> {
        var ids = Set<UUID>()
        for node in nodes {
            ids.insert(node.id)
            if let children = node.children {
                ids.formUnion(gatherAllDeviceIDs(from: children))
            }
        }
        return ids
    }
}
