import Foundation

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case top = "Top"
    case bottom = "Bottom"
    case dress = "Dress"
    case outerwear = "Outerwear"
    case shoes = "Shoes"
    case accessory = "Accessory"

    var id: String { rawValue }
}

struct Item: Codable, Identifiable {
    let id: UUID
    let ownerID: UUID
    var category: ItemCategory
    var size: String?
    var color: String?
    var occasionTags: [String]
    var caption: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case category, size, color
        case occasionTags = "occasion_tags"
        case caption
        case createdAt = "created_at"
    }
}
