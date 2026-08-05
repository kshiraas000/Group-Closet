import SwiftUI

struct MainTabView: View {
    let userID: UUID

    var body: some View {
        TabView {
            ClosetsListView(userID: userID)
                .tabItem { Label("Closets", systemImage: "door.left.hand.open") }
            Text("My Clothes")
                .tabItem { Label("My Clothes", systemImage: "tshirt") }
            Text("Profile")
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
