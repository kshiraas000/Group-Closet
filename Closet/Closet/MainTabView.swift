import SwiftUI

struct MainTabView: View {
    let userID: UUID
    let onSignedOut: () async -> Void

    var body: some View {
        TabView {
            ClosetsListView(userID: userID)
                .tabItem { Label("Closets", systemImage: "door.left.hand.open") }
            MyClothesView(userID: userID)
                .tabItem { Label("My Clothes", systemImage: "tshirt") }
            ProfileView(userID: userID, onSignedOut: onSignedOut)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
