import Foundation
import PostgREST
import Supabase

private struct MemberRow: Decodable {
    let users: UserProfile
}

private struct ItemShareRow: Decodable {
    let items: Item
}

@Observable
final class ClosetDetailViewModel {
    var members: [UserProfile] = []
    var items: [Item] = []
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    func load(closetID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        var failures: [String] = []

        do {
            let rows: [MemberRow] = try await client
                .from("closet_members")
                .select("users(id, name, photo_url, sizes)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            members = rows.map(\.users)
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            let rows: [ItemShareRow] = try await client
                .from("item_shares")
                .select("items(*)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            items = rows.map(\.items)
        } catch {
            failures.append(error.localizedDescription)
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func leave(closetID: UUID, userID: UUID) async -> Bool {
        errorMessage = nil
        do {
            try await client
                .from("closet_members")
                .delete()
                .eq("closet_id", value: closetID)
                .eq("user_id", value: userID)
                .execute()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
