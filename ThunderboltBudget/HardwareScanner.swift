import Foundation

struct HardwareScanner {
    
    // Scans exactly the same data trees, but as JSON, and decodes them into robust generic tree nodes
    func scanForDevices() -> [DeviceNode] {
        let rawData = fetchRegistryDump()
        return parseJSONOutput(rawData)
    }

    // Fetches native JSON output from the hardware profiler
    func fetchRegistryDump() -> Data {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPThunderboltDataType", "SPUSBDataType", "SPDisplaysDataType"]
        
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        } catch {
            return Data()
        }
    }

    private func parseJSONOutput(_ data: Data) -> [DeviceNode] {
        guard let root = try? JSONDecoder().decode(SPProfileRoot.self, from: data) else {
            return []
        }
        
        // 1. Map physical DisplayPort streams using our custom IOKit scanner
        let displayMappings = IORegTopologyParser.getDisplayMappings()
        
        // 2. Extract displays
        var allDisplays: [DeviceNode] = []
        if let dispNodes = root.SPDisplaysDataType {
            for gpu in dispNodes {
                if let ndrvs = gpu.spdisplays_ndrvs {
                    allDisplays.append(contentsOf: mapNodes(ndrvs, defaultIcon: "display") ?? [])
                }
            }
        }
        
        // 3. Map Thunderbolt and USB trees, and inject accessories into matched hubs
        var finalNodes: [DeviceNode] = []
        
        // Extract USB root tree
        var usbNodes: [DeviceNode] = []
        if let usbRaw = root.SPUSBDataType, let mapped = mapNodes(usbRaw, defaultIcon: "cable.connector") {
            usbNodes = mapped.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        
        if let tbNodes = root.SPThunderboltDataType,
           let mapped = mapNodes(tbNodes, defaultIcon: "bolt.fill") {
            let sortedMapped = mapped.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let injected = injectAccessories(into: sortedMapped, availableDisplays: &allDisplays, usbNodes: &usbNodes, mappings: displayMappings)
            
            // Post-process the injected nodes to add root bandwidth ratios
            var customizedRootPorts: [DeviceNode] = []
            for port in injected {
                var maxCap = 40.0
                if let oldLabel = port.bandwidthLabel, oldLabel.contains("Gb/s") {
                    maxCap = Double(oldLabel.replacingOccurrences(of: " Gb/s", with: "")) ?? 40.0
                }
                
                // Sum all endpoints under this physical port
                let totalGbps = sumBandwidth(of: [port])
                let ratio = min(totalGbps / maxCap, 1.0)
                let newLabel = String(format: "%.1f / %.0f Gb/s", totalGbps, maxCap)
                
                let newNode = DeviceNode(id: port.id, name: port.name, iconName: port.iconName, bandwidthLabel: newLabel, uid: port.uid, children: port.children, bandwidthRatio: ratio)
                customizedRootPorts.append(newNode)
            }
            
            finalNodes.append(DeviceNode(name: "Thunderbolt Bus", iconName: "bolt.circle.fill", children: customizedRootPorts))
        }
        
        if !usbNodes.isEmpty {
            finalNodes.append(DeviceNode(name: "USB Bus", iconName: "command.circle.fill", children: usbNodes))
        }
        
        // 4. Any leftover displays go into the root Displays folder
        if !allDisplays.isEmpty {
            finalNodes.append(DeviceNode(name: "Displays", iconName: "display.circle.fill", children: allDisplays))
        }
        
        return pruneEmptyHubs(from: finalNodes)
    }

    // Prune unused internal hubs (e.g. empty USB hubs that monitor structural boards expose)
    private func pruneEmptyHubs(from nodes: [DeviceNode]) -> [DeviceNode] {
        var pruned: [DeviceNode] = []
        for node in nodes {
            var mutableNode = node
            if let children = mutableNode.children {
                let remaining = pruneEmptyHubs(from: children)
                mutableNode.children = remaining.isEmpty ? nil : remaining
            }
            
            let lower = mutableNode.name.lowercased()
            let isGenericHub = lower == "usb2.0 hub" || lower == "usb2.1 hub" || lower == "usb3.0 hub" || lower == "usb3.1 hub" || lower == "hub feature controller"
            
            // Do not prune primary Thunderbolt Hubs even if empty
            let isMainTBHub = lower.contains("owc") || lower.contains("sonnet") || lower.contains("echo") || lower == "thunderbolt hub"
            
            if isGenericHub && !isMainTBHub && mutableNode.children == nil {
                continue
            }
            
            pruned.append(mutableNode)
        }
        return pruned
    }

    private func injectAccessories(into nodes: [DeviceNode], availableDisplays: inout [DeviceNode], usbNodes: inout [DeviceNode], mappings: [String: [Accessory]]) -> [DeviceNode] {
        var newNodes: [DeviceNode] = []
        for node in nodes {
            var mutableNode = node
            
            // Recurse first
            if let children = mutableNode.children {
                mutableNode.children = injectAccessories(into: children, availableDisplays: &availableDisplays, usbNodes: &usbNodes, mappings: mappings)
            }
            
            // Do we match a Hub UID?
            if let uidHex = mutableNode.uid, 
               let decStr = hexToDec(uidHex), 
               let mappedAccessories = mappings[decStr] {
                
                var matchedAccessories: [DeviceNode] = []
                
                // Pluck Displays
                for accessory in mappedAccessories {
                    if let idx = availableDisplays.firstIndex(where: { $0.name.localizedCaseInsensitiveContains(accessory.name) }) {
                        let extracted = availableDisplays.remove(at: idx)
                        let newLabel = extracted.bandwidthLabel ?? accessory.speed
                        matchedAccessories.append(DeviceNode(id: extracted.id, name: extracted.name, iconName: extracted.iconName, bandwidthLabel: newLabel, uid: extracted.uid, children: extracted.children))
                    }
                }
                
                // Pluck deeply nested USB accessories automatically
                usbNodes = extractMatching(from: usbNodes, accessories: mappedAccessories, extracted: &matchedAccessories)
                
                // Check if macOS SPUSBDataType completely failed to report the device (common bug)
                // If it missed it, but IORegistry knows it's plugged into this exact port, we synthesize it!
                for accessory in mappedAccessories {
                    let wasMatched = matchedAccessories.contains { $0.name.localizedCaseInsensitiveContains(accessory.name) }
                    
                    if !wasMatched {
                        let lower = accessory.name.lowercased()
                        // Ignore the hidden internal structural hubs that don't mean anything to users
                        if lower.contains("thunderbolt") { continue }
                        if lower == "usb2.0 hub" || lower == "usb2.1 hub" || lower == "usb3.0 hub" || lower == "usb3.1 hub" || lower == "hub feature controller" { continue }
                        
                        let syntheticIcon = accessory.name.localizedCaseInsensitiveContains("hub") ? "point.3.connected.trianglepath.dotted" : "usbplugin"
                        matchedAccessories.append(DeviceNode(name: accessory.name, iconName: syntheticIcon, bandwidthLabel: accessory.speed))
                    }
                }
                
                if !matchedAccessories.isEmpty {
                    var newChildren = mutableNode.children ?? []
                    
                    // Group USB accessories cleanly, but keep Displays at the top level of the TB Hub
                    var displays: [DeviceNode] = []
                    var usbs: [DeviceNode] = []
                    for acc in matchedAccessories {
                        if acc.iconName == "display" || acc.iconName == "display.circle.fill" || acc.iconName == "laptopcomputer" {
                            displays.append(acc)
                        } else {
                            usbs.append(acc)
                        }
                    }
                    
                    newChildren.append(contentsOf: displays)
                    if !usbs.isEmpty {
                        let totalCons = sumBandwidth(of: usbs)
                        let totalLabel = formatTotalBandwidth(totalCons)
                        
                        let accessoriesFolder = DeviceNode(id: UUID(), name: "USB Accessories", iconName: "cable.connector", bandwidthLabel: totalLabel, uid: nil, children: usbs)
                        newChildren.append(accessoriesFolder)
                    }
                    
                    mutableNode.children = newChildren
                }
            }
            newNodes.append(mutableNode)
        }
        return newNodes
    }
    
    private func sumBandwidth(of nodes: [DeviceNode]) -> Double {
        var total: Double = 0.0
        for node in nodes {
            if let children = node.children, !children.isEmpty {
                // To avoid double-counting hub uplinks and downstream devices, we only sum the leaf endpoints
                total += sumBandwidth(of: children)
            } else {
                if let label = node.bandwidthLabel {
                    if label.contains("Gbps") {
                        let val = Double(label.replacingOccurrences(of: " Gbps", with: "")) ?? 0.0
                        total += val
                    } else if label.contains("Mbps") {
                        let val = Double(label.replacingOccurrences(of: " Mbps", with: "")) ?? 0.0
                        total += val / 1000.0
                    }
                }
            }
        }
        return total
    }
    
    private func formatTotalBandwidth(_ total: Double) -> String {
        if total == 0.0 { return "0 Mbps" }
        if total >= 1.0 {
            return String(format: "%.1f Gbps", total)
        } else {
            return String(format: "%.0f Mbps", total * 1000.0)
        }
    }
    
    // Scours a tree recursively and permanently rips out any nodes that match the names array
    private func extractMatching(from nodes: [DeviceNode], accessories: [Accessory], extracted: inout [DeviceNode]) -> [DeviceNode] {
        var keptNodes: [DeviceNode] = []
        for node in nodes {
            var mutableNode = node
            
            var matchedAccessory: Accessory? = nil
            for acc in accessories {
                if mutableNode.name.localizedCaseInsensitiveContains(acc.name) {
                    matchedAccessory = acc
                    break
                }
            }
            
            if let acc = matchedAccessory {
                let newLabel = mutableNode.bandwidthLabel ?? acc.speed
                let finalNode = DeviceNode(id: mutableNode.id, name: mutableNode.name, iconName: mutableNode.iconName, bandwidthLabel: newLabel, uid: mutableNode.uid, children: mutableNode.children)
                extracted.append(finalNode)
            } else {
                if let children = mutableNode.children {
                    let remaining = extractMatching(from: children, accessories: accessories, extracted: &extracted)
                    mutableNode.children = remaining.isEmpty ? nil : remaining
                }
                keptNodes.append(mutableNode)
            }
        }
        return keptNodes
    }
    
    private func hexToDec(_ hex: String) -> String? {
        let cleanHex = hex.replacingOccurrences(of: "0x", with: "")
        if let val = UInt64(cleanHex, radix: 16) {
            return String(val)
        }
        return nil
    }

    private func mapNodes(_ nodes: [SPNode], defaultIcon: String) -> [DeviceNode]? {
        guard !nodes.isEmpty else { return nil }
        
        var result: [DeviceNode] = []
        for node in nodes {
            var name = node._name ?? "Unknown Device"
            let uid = node.switch_uid_key // Needed for our topology mapper
            var children: [DeviceNode]? = nil
            var iconName = defaultIcon
            
            // 1. Clean up underlying bus connections and inject physical Port Mappings
            if name.hasPrefix("thunderboltusb4_bus_") || name.hasPrefix("thunderbolt_bus_") {
                let busStr = name.replacingOccurrences(of: "thunderboltusb4_bus_", with: "").replacingOccurrences(of: "thunderbolt_bus_", with: "")
                if let busID = Int(busStr) {
                    name = HardwareScanner.mapPhysicalPortLocation(forBus: busID)
                } else {
                    name = "Thunderbolt Port"
                }
            }
            
            // 2. Inject Vendor Names for generic labels (like "Thunderbolt Hub")
            if let vendor = node.vendor_name_key, vendor != "Apple Inc." {
                // Shorten some overly-long corporate names
                let shortVendor = vendor.replacingOccurrences(of: "Other World Computing", with: "OWC")
                                        .replacingOccurrences(of: " Technologies, Inc.", with: "")
                                        .replacingOccurrences(of: ", Inc.", with: "")
                
                // Only prepend if the device doesn't already have the brand in the name
                if !name.localizedCaseInsensitiveContains(shortVendor) {
                    name = "\(shortVendor) \(name)"
                }
            }
            
            if node.spdisplays_connection_type == "spdisplays_internal" {
                name = "Built-In Display"
                iconName = "laptopcomputer"
            }
            
            if let items = node._items {
                children = mapNodes(items, defaultIcon: defaultIcon)
            }
            
            var bwLabel: String? = nil
            if let res = node._spdisplays_resolution {
                let cleanRes = res.replacingOccurrences(of: ".00Hz", with: "Hz")
                name = "\(name) (\(cleanRes))"
                
                if let bw = self.calculateDisplayBandwidth(res) {
                    bwLabel = String(format: "%.1f Gbps", bw)
                }
            } else if let speed = node.receptacle_upstream_ambiguous_tag?.current_speed_key ?? node.receptacle_1_tag?.current_speed_key {
                bwLabel = speed.contains("Up to") ? nil : speed
            }
            
            result.append(DeviceNode(name: name, iconName: iconName, bandwidthLabel: bwLabel, uid: uid, children: children))
        }
        return result.isEmpty ? nil : result
    }

    // Example resolution string: "3440 x 1440 @ 60.00Hz"
    private func calculateDisplayBandwidth(_ res: String) -> Double? {
        let parts = res.replacingOccurrences(of: "Hz", with: "").components(separatedBy: .whitespaces)
        let numbers = parts.compactMap { Double($0) }
        
        if numbers.count >= 3 {
            let width = numbers[0]
            let height = numbers[1]
            let refresh = numbers[2]
            
            let bandwidth = (width * height * refresh * 24.0 * 1.2) / 1_000_000_000.0
            return bandwidth
        }
        return nil
    }

    // Detect macOS Model and map internal bus indexes to literal chassis holes.
    static func mapPhysicalPortLocation(forBus bus: Int) -> String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)
        
        // Advanced Apple Silicon Pro/Max Chassis Port Detection lookup tables
        switch modelString {
        case "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11": // M2/M3 MacBook Pro 14"/16"
            if bus == 0 { return "Left Back Port" }
            if bus == 1 { return "Left Front Port" }
            if bus == 2 { return "Right Port" }
        case "Mac13,1", "Mac13,2", "Mac14,13", "Mac14,14": // M1/M2 Mac Studio
            if bus == 0 { return "Back Port 1 (Top Left)" }
            if bus == 1 { return "Back Port 2" }
            if bus == 2 { return "Back Port 3" }
            if bus == 3 { return "Back Port 4 (Bottom Right)" }
            if bus == 4 { return "Front Port 1 (Left)" }
            if bus == 5 { return "Front Port 2 (Right)" }
        // Default generic heuristics based on architectural lineage
        default:
            if modelString.contains("MacBookPro") {
                if bus == 0 { return "Left Back Port" }
                if bus == 1 { return "Left Front Port" }
                if bus == 2 { return "Right Port" }
            } else if modelString.contains("MacBookAir") {
                if bus == 0 { return "Left Back Port" }
                if bus == 1 { return "Left Front Port" }
            } else if modelString.contains("Macmini") {
                if bus == 0 { return "Back Left Port" }
                if bus == 1 { return "Back Right Port" }
            }
        }
        
        return "Thunderbolt Port \(bus + 1)"
    }
}
