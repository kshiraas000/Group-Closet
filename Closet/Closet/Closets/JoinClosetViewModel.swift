import Foundation
import PostgREST
import Supabase

@Observable
final class JoinClosetViewModel {
    var inviteCode: String = ""
    var isJoining = false
    var errorMessage: String?

    private let client = SupabaseService.shared

    func join() async -> Closet? {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorMessage = "Invite code is required"
            return nil
        }
        isJoining = true
        defer { isJoining = false }

        do {
            let closet: Closet = try await client
                .rpc("join_closet_by_invite_code", params: ["p_invite_code": code])
                .execute()
                .value
            return closet
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
