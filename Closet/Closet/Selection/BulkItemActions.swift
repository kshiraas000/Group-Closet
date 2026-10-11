import Foundation
import PostgREST
import Storage
import Supabase

/// Supabase writes for select mode. RLS only lets these succeed on the
/// caller's own items, which is also the only thing select mode can select.
enum BulkItemActions {
    private static var client: SupabaseClient { SupabaseService.shared }

    /// Rows first, then storage — same order and reason as
    /// ItemDetailViewModel.deleteItem: if the row delete fails nothing has
    /// changed; a dangling storage object is harmless, a dangling row is not.
    static func delete(_ items: [BrowseItem]) async throws {
        guard !items.isEmpty else { return }
        try await client
            .from("items")
            .delete()
            .in("id", values: items.map(\.id))
            .execute()
        let paths = items.compactMap(\.photoPath)
        if !paths.isEmpty {
            _ = try? await client.storage.from("item-photos").remove(paths: paths)
        }
    }

    /// ignoreDuplicates (ON CONFLICT DO NOTHING) so pieces already in the
    /// closet don't trip the (item_id, closet_id) primary key. DO NOTHING
    /// needs only INSERT privilege, unlike DO UPDATE.
    static func addShares(itemIDs: [UUID], closetID: UUID) async throws {
        guard !itemIDs.isEmpty else { return }
        struct NewShare: Encodable {
            let itemID: UUID
            let closetID: UUID
            enum CodingKeys: String, CodingKey {
                case itemID = "item_id"
                case closetID = "closet_id"
            }
        }
        try await client
            .from("item_shares")
            .upsert(
                itemIDs.map { NewShare(itemID: $0, closetID: closetID) },
                onConflict: "item_id,closet_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    static func removeShares(itemIDs: [UUID], closetID: UUID) async throws {
        guard !itemIDs.isEmpty else { return }
        try await client
            .from("item_shares")
            .delete()
            .eq("closet_id", value: closetID)
            .in("item_id", values: itemIDs)
            .execute()
    }

    /// One update per item: appended occasions make each row's new value
    /// different. Only the column-granted fields are sent (see the
    /// tighten_items_edit_delete migration).
    static func apply(_ edit: BulkEdit, to items: [Item]) async throws {
        guard !edit.isEmpty else { return }
        struct ItemUpdate: Encodable {
            let category: ItemCategory
            let size: String?
            let color: String?
            let occasionTags: [String]
            enum CodingKeys: String, CodingKey {
                case category, size, color
                case occasionTags = "occasion_tags"
            }
        }
        for item in items {
            let updated = edit.applied(to: item)
            try await client
                .from("items")
                .update(ItemUpdate(
                    category: updated.category,
                    size: updated.size,
                    color: updated.color,
                    occasionTags: updated.occasionTags
                ))
                .eq("id", value: item.id)
                .execute()
        }
    }
}
