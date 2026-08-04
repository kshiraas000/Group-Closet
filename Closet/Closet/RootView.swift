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
            } else if hasProfile == nil {
                ProgressView().task { await checkProfile() }
            } else if hasProfile == true {
                MainTabView()
            } else if let userID = authViewModel.session?.user.id {
                OnboardingView(userID: userID) {
                    hasProfile = true
                }
            }
        }
    }

    private func checkProfile() async {
        guard let userID = authViewModel.session?.user.id else {
            hasProfile = false
            return
        }
        let count = (try? await SupabaseService.shared
            .from("users")
            .select("id", head: true, count: .exact)
            .eq("id", value: userID)
            .execute()
            .count) ?? 0
        hasProfile = count > 0
    }
}
