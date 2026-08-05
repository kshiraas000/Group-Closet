import Foundation
import PostgREST
import Supabase

private struct MemberRow: Decodable {
    let users: UserProfile
}

@Observable
final class ClosetDetailViewModel {
    var members: [UserProfile] = []
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    func loadMembers(closetID: UUID) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [MemberRow] = try await client
                .from("closet_members")
                .select("users(id, name, photo_url, sizes)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            members = rows.map(\.users)
        } catch {
            errorMessage = error.localizedDescription
        }
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
