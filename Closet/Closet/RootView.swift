import SwiftUI
import PostgREST
import Supabase

struct RootView: View {
    let authViewModel: AuthViewModel
    @State private var hasProfile: Bool?

    var body: some View {
        Group {
            if authViewModel.isLoading {
                ProgressView()
            } else if authViewModel.session == nil {
                SignInView(authViewModel: authViewModel)
            } else if let userID = authViewModel.session?.user.id {
                if hasProfile == nil {
                    ProgressView().task { await checkProfile(userID: userID) }
                } else if hasProfile == true {
                    MainTabView(userID: userID)
                } else {
                    OnboardingView(userID: userID) {
                        hasProfile = true
                    }
                }
            }
        }
    }

    private func checkProfile(userID: UUID) async {
        do {
            let count = try await SupabaseService.shared
                .from("users")
                .select("id", head: true, count: .exact)
                .eq("id", value: userID)
                .execute()
                .count ?? 0
            hasProfile = count > 0
        } catch {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await checkProfile(userID: userID)
        }
    }
}
