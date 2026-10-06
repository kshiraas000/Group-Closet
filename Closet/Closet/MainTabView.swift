import SwiftUI

struct MainTabView: View {
    let userID: UUID
    let onSignedOut: () async -> Void
    @State private var selectedTab: Tab = .closets
    // Lives here, not in ClosetsListView: switching tabs rebuilds the tab's
    // content from scratch, so the "which closet am I in" state has to be
    // owned by something that outlives it.
    @State private var closetNavigation: ClosetNavigationStore
    /// Same reason as closetNavigation: every tab's content is rebuilt from
    /// scratch on each switch, so each tab's own view model has to live here
    /// instead to survive that — otherwise returning to a tab flashed a
    /// spinner and refetched from scratch every time. Resets on sign-out
    /// with this view. (A given closet's own view model is cached inside
    /// closetNavigation instead, since there can be many closets.)
    @State private var closetsViewModel = ClosetsViewModel()
    @State private var myClothesViewModel = MyClothesViewModel()
    @State private var profileViewModel = ProfileViewModel()

    init(userID: UUID, onSignedOut: @escaping () async -> Void) {
        self.userID = userID
        self.onSignedOut = onSignedOut
        _closetNavigation = State(initialValue: ClosetNavigationStore(userID: userID))
    }

    enum Tab {
        case closets, myClothes, profile
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .closets:
                    ClosetsListView(navigation: closetNavigation, viewModel: closetsViewModel, userID: userID)
                case .myClothes:
                    MyClothesView(viewModel: myClothesViewModel, userID: userID)
                case .profile:
                    // Covers account deletion too — ProfileView routes both
                    // through onSignedOut.
                    ProfileView(viewModel: profileViewModel, userID: userID, onSignedOut: {
                        closetNavigation.clear()
                        await onSignedOut()
                    })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(Theme.Color.background)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(tab: .closets, systemImage: "door.left.hand.open", label: "Closets")
            tabButton(tab: .myClothes, systemImage: "tshirt", label: "My Clothes")
            tabButton(tab: .profile, systemImage: "person.crop.circle", label: "Profile")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.Color.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Color.divider)
                .frame(height: 0.5)
        }
    }

    private func tabButton(tab: Tab, systemImage: String, label: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            // Re-tapping the current Closets tab backs out to the list, the
            // same as the back button.
            if isSelected, tab == .closets {
                closetNavigation.requestPopToRoot()
            }
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(label)
                    .font(Theme.Font.body(10, weight: .medium))
            }
            .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.tertiaryText)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
