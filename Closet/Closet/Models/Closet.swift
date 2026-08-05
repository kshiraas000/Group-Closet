import Foundation

struct Closet: Codable, Identifiable {
    let id: UUID
    var name: String
    let inviteCode: String
    let createdBy: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}
