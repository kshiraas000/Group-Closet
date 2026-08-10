import SwiftUI

struct MainTabView: View {
    let userID: UUID
    let onSignedOut: () async -> Void

    init(userID: UUID, onSignedOut: @escaping () async -> Void) {
        self.userID = userID
        self.onSignedOut = onSignedOut
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.Color.background)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            ClosetsListView(userID: userID)
                .tabItem { Label("Closets", systemImage: "door.left.hand.open") }
            MyClothesView(userID: userID)
                .tabItem { Label("My Clothes", systemImage: "tshirt") }
            ProfileView(userID: userID, onSignedOut: onSignedOut)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Theme.Color.accent)
    }
}
