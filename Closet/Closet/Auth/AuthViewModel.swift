import Foundation
import Supabase

@Observable
final class AuthViewModel {
    var session: Session?
    var isLoading = true

    private let client = SupabaseService.shared

    init() {
        Task { await loadSession() }
    }

    func loadSession() async {
        let localSession = try? await client.auth.session
        session = (localSession?.isExpired == false) ? localSession : nil
        isLoading = false
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
        session = nil
    }
}
