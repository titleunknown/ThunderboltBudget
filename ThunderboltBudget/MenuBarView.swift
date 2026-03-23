import SwiftUI

struct MenuBarView: View {
    @ObservedObject var manager = HardwareManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let ports = manager.deviceTrees.first { $0.name == "Thunderbolt Bus" }?.children ?? []
            
            if ports.isEmpty {
                Text(manager.isScanning ? "Scanning..." : "No Thunderbolt Ports Active")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(ports) { port in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.blue)
                            Text(port.name)
                                .font(.system(.body, design: .rounded))
                            
                            Spacer(minLength: 20)
                            
                            if let bw = port.bandwidthLabel {
                                Text(bw)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(pillColor(for: port))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                        if let ratio = port.bandwidthRatio {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                    
                                    Rectangle()
                                        .fill(pillColor(for: port))
                                        .frame(width: max(0, min(CGFloat(ratio), 1.0) * geo.size.width))
                                }
                            }
                            .frame(height: 3)
                            .cornerRadius(1.5)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            
            HStack {
                Text(String(format: "Total Consumption: %.1f Gbps", manager.gatherSystemTotal()))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 380)
    }
    
    private func pillColor(for node: DeviceNode) -> Color {
        guard let ratio = node.bandwidthRatio else {
            return Color.blue.opacity(0.8)
        }
        if ratio >= 0.80 { return Color.red }
        else if ratio >= 0.50 { return Color.orange }
        else { return Color.green }
    }
}
