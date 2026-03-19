import Foundation

struct SPProfileRoot: Codable {
    var SPThunderboltDataType: [SPNode]?
    var SPUSBDataType: [SPNode]?
    var SPDisplaysDataType: [SPNode]?
}

struct SPNode: Codable {
    var _name: String?
    var _items: [SPNode]?
    var spdisplays_ndrvs: [SPNode]?
    
    // New keys for bandwidth calculation
    var _spdisplays_resolution: String?
    var receptacle_upstream_ambiguous_tag: ReceptacleTag?
    var receptacle_1_tag: ReceptacleTag?
    var switch_uid_key: String?
    var spdisplays_connection_type: String?
    var vendor_name_key: String?
}

struct ReceptacleTag: Codable {
    var current_speed_key: String?
}

struct DeviceNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let iconName: String
    let bandwidthLabel: String?
    let uid: String?
    var children: [DeviceNode]?
    var bandwidthRatio: Double?
    
    init(id: UUID = UUID(), name: String, iconName: String = "cube", bandwidthLabel: String? = nil, uid: String? = nil, children: [DeviceNode]? = nil, bandwidthRatio: Double? = nil) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.bandwidthLabel = bandwidthLabel
        self.uid = uid
        self.children = children
        self.bandwidthRatio = bandwidthRatio
    }
}
