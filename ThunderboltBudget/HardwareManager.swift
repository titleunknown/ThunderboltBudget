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
    
    init() {
        HardwareWatcher.shared.onHardwareChanged = { [weak self] in
            Task { @MainActor in
                self?.performScan()
            }
        }
        HardwareWatcher.shared.startMonitoring()
        LiveAnalytics.shared.start()
        performScan()
    }
    
    func performScan() {
        guard !isScanning else { return }
        isScanning = true
        
        Task {
            let (scannedTrees, allIDs) = await Task.detached(priority: .userInitiated) {
                // The HardwareScanner is now a Struct, rendering it immune to @MainActor inference contamination.
                let scanner = HardwareScanner()
                let trees = scanner.scanForDevices()
                let ids = UIBackgroundWorkers.gatherAllDeviceIDs(from: trees)
                return (trees, ids)
            }.value
            
            // Re-sync with MainActor context
            self.deviceTrees = scannedTrees
            self.expandedNodes = allIDs
            self.isScanning = false
        }
    }
    
    func gatherSystemTotal() -> Double {
        var total = 0.0
        if let bus = deviceTrees.first(where: { $0.name == "Thunderbolt Bus" }), let ports = bus.children {
            for port in ports {
                if let label = port.bandwidthLabel {
                    let parts = label.components(separatedBy: "/")
                    if let valStr = parts.first?.trimmingCharacters(in: .whitespaces), let val = Double(valStr) {
                        total += val
                    }
                }
            }
        }
        return total
    }
    
    func copyMarkdownAction() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        let text = UIBackgroundWorkers.generateHardwareMarkdown(from: deviceTrees)
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Thread-Safe Pure Functions
// Wrapping these in a strict generic struct mathematically prevents Swift 6 from inferring @MainActor from the file's primary class
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
