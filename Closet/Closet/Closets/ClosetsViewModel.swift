import Foundation
import PostgREST
import Supabase

private struct ClosetIDRow: Decodable {
    let closetID: UUID

    enum CodingKeys: String, CodingKey {
        case closetID = "closet_id"
    }
}

@Observable
final class ClosetsViewModel {
    var closets: [Closet] = []
    var memberCounts: [UUID: Int] = [:]
    var pieceCounts: [UUID: Int] = [:]
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    func loadClosets() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            closets = try await client
                .from("closets")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        await loadCounts()
    }

    // These report failure by return value rather than errorMessage: on the
    // list screen errorMessage replaces the whole list, which would strand
    // the user on an error page over a failed delete.
    func leave(closetID: UUID, userID: UUID) async -> Bool {
        do {
            try await client
                .from("closet_members")
                .delete()
                .eq("closet_id", value: closetID)
                .eq("user_id", value: userID)
                .execute()
            return true
        } catch {
            return false
        }
    }

    /// Deletes the closet for everyone. RLS allows this only for the creator, or
    /// for any member once the creator has deleted their account.
    func deleteCloset(closetID: UUID) async -> Bool {
        do {
            try await client
                .from("closets")
                .delete()
                .eq("id", value: closetID)
                .execute()
            return true
        } catch {
            return false
        }
    }

    /// Row counts for the "N members · N pieces" subtitle. Failures here leave
    /// the subtitle off rather than blanking the whole list — the names are
    /// the load-bearing content.
    private func loadCounts() async {
        if let rows: [ClosetIDRow] = try? await client
            .from("closet_members")
            .select("closet_id")
            .execute()
            .value {
            memberCounts = rows.reduce(into: [:]) { counts, row in
                counts[row.closetID, default: 0] += 1
            }
        }

        // items!inner, never a plain items embed: a to-one embed is a LEFT
        // JOIN, so an RLS-denied item comes back as {"items": null} and one
        // null fails the whole decode. !inner drops those rows instead —
        // which is also the correct count, since a blocked item isn't visible.
        if let rows: [ClosetIDRow] = try? await client
            .from("item_shares")
            .select("closet_id, items!inner(id)")
            .execute()
            .value {
            pieceCounts = rows.reduce(into: [:]) { counts, row in
                counts[row.closetID, default: 0] += 1
            }
        }
    }
}
