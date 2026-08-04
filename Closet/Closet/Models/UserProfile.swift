import Foundation

struct UserProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var photoURL: String?
    var sizes: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case photoURL = "photo_url"
        case sizes
    }
}
