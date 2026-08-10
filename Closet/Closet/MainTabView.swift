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
        let labelFont = UIFont(name: "DMSans-Medium", size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .medium)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.font: labelFont]
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.font: labelFont]
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
