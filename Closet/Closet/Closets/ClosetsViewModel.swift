import Foundation
import PostgREST
import Supabase

private struct ClosetIDRow: Decodable {
    let closetID: UUID

    enum CodingKeys: String, CodingKey {
        case closetID = "closet_id"
    }
}

private struct MemberRow: Decodable {
    let closetID: UUID
    let users: UserProfile

    enum CodingKeys: String, CodingKey {
        case closetID = "closet_id"
        case users
    }
}

@Observable
final class ClosetsViewModel {
    var closets: [Closet] = []
    /// Each closet's members, for the row avatars and member count.
    var members: [UUID: [UserProfile]] = [:]
    var memberPhotoURLs: [UUID: URL] = [:]
    var pieceCounts: [UUID: Int] = [:]
    var isLoading = true
    var errorMessage: String?

    var memberCounts: [UUID: Int] {
        members.mapValues(\.count)
    }

    private let client = SupabaseService.shared

    func loadClosets() async {
        errorMessage = nil
        isLoading = true
        do {
            closets = try await client
                .from("closets")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        await loadCounts()
        isLoading = false

        // Signed after the list is showing, not before: avatars fall back to
        // initials until these land, so the list never waits on them.
        let everyone = Dictionary(members.values.joined().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        memberPhotoURLs = await ProfilePhotoResolver.signedURLs(for: Array(everyone.values))
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
        // users!inner for the same reason as items!inner below: a member
        // whose profile RLS hides would otherwise come back as null and fail
        // the whole decode.
        if let rows: [MemberRow] = try? await client
            .from("closet_members")
            .select("closet_id, users!inner(id, name, photo_url, sizes)")
            .order("joined_at")
            .execute()
            .value {
            members = Dictionary(grouping: rows, by: \.closetID).mapValues { $0.map(\.users) }
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
