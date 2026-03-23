import Foundation

struct ThunderboltDevice: Identifiable {
    let id = UUID()
    var name: String
    var speed: String       // e.g., "40 Gbps"
    var isConnected: Bool
    var estimatedBandwidthUsage: Double // We'll calculate this later
}