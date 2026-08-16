import Foundation
import PostgREST
import Storage
import Supabase
import UIKit

enum SaveState: Equatable {
    case pending
    case saving
    case saved
    case failed(String)
}

struct DraftItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var category: ItemCategory?
    var size: String = ""
    var color: String = ""
    var occasionTags: String = ""
    var caption: String = ""
    var saveState: SaveState = .pending
}

@Observable
final class AddItemViewModel {
    var draftItems: [DraftItem] = []
    var shareToClosetIDs: Set<UUID> = []
    private var defaultSizes: [String: String] = [:]

    private let client = SupabaseService.shared

    func loadDefaultSizes(userID: UUID) async {
        struct SizesRow: Decodable { let sizes: [String: String] }
        let row: SizesRow? = try? await client
            .from("users")
            .select("sizes")
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        defaultSizes = row?.sizes ?? [:]
    }

    func startTagging(images: [UIImage]) {
        draftItems = images.map { DraftItem(image: $0) }
    }

    func addImages(_ images: [UIImage]) {
        draftItems.append(contentsOf: images.map { DraftItem(image: $0) })
    }

    func selectCategory(_ category: ItemCategory, forItemAt index: Int) {
        let previousDefault = draftItems[index].category.map { defaultSize(for: $0) } ?? ""
        let currentSize = draftItems[index].size
        draftItems[index].category = category
        // Only refill the size if it still matches the prior category's
        // auto-fill (or is empty) — otherwise a manually typed size would
        // get silently clobbered by switching categories.
        if currentSize.isEmpty || currentSize == previousDefault {
            draftItems[index].size = defaultSize(for: category)
        }
    }

    private func defaultSize(for category: ItemCategory) -> String {
        switch category {
        case .top: return defaultSizes["top"] ?? ""
        case .bottom: return defaultSizes["bottom"] ?? ""
        case .shoes: return defaultSizes["shoe"] ?? ""
        case .dress, .outerwear, .accessory: return ""
        }
    }

    func saveAll(currentClosetID: UUID, ownerID: UUID) async {
        for index in draftItems.indices {
            guard draftItems[index].saveState != .saved else { continue }
            await save(itemAt: index, currentClosetID: currentClosetID, ownerID: ownerID)
        }
    }

    func save(itemAt index: Int, currentClosetID: UUID, ownerID: UUID) async {
        draftItems[index].saveState = .saving
        let draft = draftItems[index]
        guard let category = draft.category else {
            draftItems[index].saveState = .failed("Missing category")
            return
        }

        do {
            let itemID = draft.id
            guard let imageData = ImageCompressor.compress(draft.image) else {
                draftItems[index].saveState = .failed("Could not process image")
                return
            }
            // Lowercased: Swift's UUID interpolation is uppercase, but Postgres's
            // uuid::text cast (used by storage.objects' RLS policies) is always
            // lowercase — an uppercase path segment would never match auth.uid()::text.
            let ownerSegment = ownerID.uuidString.lowercased()
            let itemSegment = itemID.uuidString.lowercased()
            let path = "\(ownerSegment)/\(itemSegment)/0.jpg"

            try await client.storage.from("item-photos").upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

            let occasionTags = draft.occasionTags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // save() can be re-invoked on the same itemID via the retry button
            // after a partial prior failure. item_photos/item_shares only grant
            // SELECT+INSERT to authenticated, so idempotency comes from checking
            // whether each row already exists before inserting it, not from
            // ON CONFLICT DO UPDATE (which needs UPDATE privilege Postgres
            // enforces even when nothing would change).
            if try await !rowExists(table: "items", column: "id", value: itemID) {
                let newItem = NewItem(
                    id: itemID,
                    ownerID: ownerID,
                    category: category,
                    size: draft.size.isEmpty ? nil : draft.size,
                    color: draft.color.isEmpty ? nil : draft.color,
                    occasionTags: occasionTags,
                    caption: draft.caption.isEmpty ? nil : draft.caption
                )
                try await client.from("items").insert(newItem).execute()
            }

            if try await !rowExists(table: "item_photos", column: "item_id", value: itemID) {
                let newPhoto = NewItemPhoto(itemID: itemID, photoURL: path, position: 0)
                try await client.from("item_photos").insert(newPhoto).execute()
            }

            var closetIDs = shareToClosetIDs
            closetIDs.insert(currentClosetID)
            let alreadyShared = try await existingShareClosetIDs(itemID: itemID)
            let missingShares = closetIDs.subtracting(alreadyShared)
            if !missingShares.isEmpty {
                let shares = missingShares.map { NewItemShare(itemID: itemID, closetID: $0) }
                try await client.from("item_shares").insert(shares).execute()
            }

            draftItems[index].saveState = .saved
        } catch {
            draftItems[index].saveState = .failed(error.localizedDescription)
        }
    }

    private func rowExists(table: String, column: String, value: UUID) async throws -> Bool {
        let count = try await client
            .from(table)
            .select(column, head: true, count: .exact)
            .eq(column, value: value)
            .execute()
            .count ?? 0
        return count > 0
    }

    private func existingShareClosetIDs(itemID: UUID) async throws -> Set<UUID> {
        struct ShareRow: Decodable {
            let closetID: UUID
            enum CodingKeys: String, CodingKey { case closetID = "closet_id" }
        }
        let rows: [ShareRow] = try await client
            .from("item_shares")
            .select("closet_id")
            .eq("item_id", value: itemID)
            .execute()
            .value
        return Set(rows.map(\.closetID))
    }
}

private struct NewItem: Encodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case category, size, color
        case occasionTags = "occasion_tags"
        case caption
    }
}

private struct NewItemPhoto: Encodable {
    let itemID: UUID
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case photoURL = "photo_url"
        case position
    }
}

private struct NewItemShare: Encodable {
    let itemID: UUID
    let closetID: UUID

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case closetID = "closet_id"
    }
}
