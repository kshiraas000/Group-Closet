import SwiftUI

struct ClosetsListView: View {
    // Owned by MainTabView, not @State here — see MainTabView.closetsViewModel.
    @Bindable var viewModel: ClosetsViewModel
    @State private var showingCreate = false
    @State private var showingJoin = false
    @State private var pendingRemoval: Closet?
    @State private var showingRemovalError = false
    @State private var path: [UUID]
    let navigation: ClosetNavigationStore
    let userID: UUID

    init(navigation: ClosetNavigationStore, viewModel: ClosetsViewModel, userID: UUID) {
        self.navigation = navigation
        self.viewModel = viewModel
        self.userID = userID
        // Seeded synchronously: the stack is already inside the closet on its
        // very first render, so no Closets list and no push animation is ever
        // visible when returning to this tab.
        _path = State(initialValue: navigation.initialPath())
    }

    private var sortedClosets: [Closet] {
        navigation.sorted(viewModel.closets)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                Group {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.closets.isEmpty {
                        emptyState
                    } else {
                        closetRows
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.Color.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { closetID in
                // Falls back to the cached closet so a restored stack can
                // render before the closets request has come back, and to a
                // loading state rather than an empty page if neither has it
                // yet — an unresolved destination used to render blank.
                if let closet = viewModel.closets.first(where: { $0.id == closetID })
                    ?? navigation.cachedCloset(id: closetID) {
                    ClosetDetailView(
                        viewModel: navigation.detailViewModel(for: closet.id),
                        closet: closet,
                        userID: userID
                    ) {
                        navigation.forget(closet.id)
                        Task { await viewModel.loadClosets() }
                    }
                } else {
                    unresolvedClosetView(closetID)
                }
            }
            .onAppear {
                // Reconcile the synchronously-seeded path back into the store
                // (onChange doesn't fire for a State's initial value).
                if let opened = path.last {
                    navigation.markOpened(opened)
                    navigation.didAutoOpen = true
                }
            }
            .task {
                await viewModel.loadClosets()
                restoreNavigation()
            }
            .onChange(of: path) { _, newPath in
                navigation.openClosetID = newPath.last
                if let opened = newPath.last {
                    navigation.markOpened(opened)
                }
            }
            .onChange(of: navigation.popToRootRequests) { _, _ in
                path.removeAll()
            }
            .sheet(isPresented: $showingCreate) {
                CreateClosetView { closetID in
                    Task {
                        await viewModel.loadClosets()
                        path = [closetID]
                    }
                }
            }
            .sheet(isPresented: $showingJoin) {
                JoinClosetView { closetID in
                    Task {
                        await viewModel.loadClosets()
                        path = [closetID]
                    }
                }
            }
            .confirmationDialog(
                removalTitle,
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingRemoval
            ) { closet in
                Button(canDelete(closet) ? "Delete for Everyone" : "Leave", role: .destructive) {
                    Task { await confirmRemoval(of: closet) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { closet in
                Text(removalMessage(for: closet))
            }
            .alert("Something went wrong. Please try again.", isPresented: $showingRemovalError) {
                Button("OK") {}
            }
        }
    }

    private var removalTitle: String {
        guard let closet = pendingRemoval else { return "" }
        return canDelete(closet) ? "Delete \(closet.name)?" : "Leave \(closet.name)?"
    }

    /// Same wording as the dialogs inside ClosetDetailView.
    private func removalMessage(for closet: Closet) -> String {
        if canDelete(closet) {
            return "This deletes the closet for everyone, not just you. Nobody will be able to open it or use the invite code again. Everyone keeps their own clothes in My Clothes."
        }
        if (viewModel.memberCounts[closet.id] ?? 0) <= 1 {
            return "You're the last member. Leaving will delete \(closet.name) for good, including its invite code."
        }
        return ""
    }

    /// Re-enters the closet the user was last inside (so a tab switch or a
    /// relaunch lands where they left off), or — the first time only —
    /// auto-opens their most recent / only closet.
    /// Covers only what the synchronous seed couldn't know without the
    /// network — chiefly a first-ever visit, where there's no cache yet and
    /// a lone closet should open on its own.
    private func restoreNavigation() {
        navigation.cacheClosets(viewModel.closets)

        guard path.isEmpty, !navigation.didAutoOpen else {
            navigation.didAutoOpen = true
            return
        }
        navigation.didAutoOpen = true

        if let target = navigation.autoOpenTarget(in: viewModel.closets) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { path = [target] }
        }
    }

    /// Shown when a restored closet id can't be resolved yet. Loads, then
    /// drops back to the list if the closet is genuinely gone (left/deleted)
    /// rather than leaving the user on a dead screen.
    private func unresolvedClosetView(_ closetID: UUID) -> some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .task {
                if viewModel.closets.isEmpty {
                    await viewModel.loadClosets()
                    navigation.cacheClosets(viewModel.closets)
                }
                if !viewModel.closets.contains(where: { $0.id == closetID }) {
                    navigation.forget(closetID)
                    path = []
                }
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Closets")
                .font(Theme.Font.headline(32))
                .foregroundStyle(Theme.Color.primaryText)

            HStack(spacing: 8) {
                actionPill("Create Closet", systemImage: "plus", isPrimary: true) {
                    showingCreate = true
                }
                actionPill("Join with Code", systemImage: "number", isPrimary: false) {
                    showingJoin = true
                }
            }

            if !viewModel.isLoading, !viewModel.closets.isEmpty {
                Text("Your Closets · \(viewModel.closets.count)")
                    .font(Theme.Font.body(13, weight: .medium))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func actionPill(
        _ title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Theme.Font.body(13.5, weight: .medium))
            }
            .foregroundStyle(isPrimary ? Theme.Color.background : Theme.Color.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isPrimary ? Theme.Color.accent : Theme.Color.primaryText.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // A List (styled to look like the old plain stack) rather than a
    // ScrollView, because .swipeActions only works on List rows.
    private var closetRows: some View {
        List {
            ForEach(sortedClosets) { closet in
                closetRow(closet)
                    .listRowInsets(EdgeInsets(top: 3, leading: 20, bottom: 3, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.Color.background)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Not role: .destructive — that animates the row away
                        // immediately, before the user has confirmed.
                        Button(canDelete(closet) ? "Delete" : "Leave") {
                            pendingRemoval = closet
                        }
                        .tint(.red)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 6, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .refreshable {
            await viewModel.loadClosets()
        }
    }

    /// Mirrors the DELETE policy on public.closets: the creator, or any member
    /// once the creator has deleted their account and created_by went null.
    private func canDelete(_ closet: Closet) -> Bool {
        closet.createdBy == userID || closet.createdBy == nil
    }

    private func confirmRemoval(of closet: Closet) async {
        let success = canDelete(closet)
            ? await viewModel.deleteCloset(closetID: closet.id)
            : await viewModel.leave(closetID: closet.id, userID: userID)
        if success {
            navigation.forget(closet.id)
            await viewModel.loadClosets()
        } else {
            showingRemovalError = true
        }
    }

    /// Laid out star · text · chevron so a closet picture (photo, initials or
    /// emoji, like a contact photo) can later slot in as a ~40pt circle
    /// between the star and the name without reworking the row.
    private func closetRow(_ closet: Closet) -> some View {
        let isFavorite = navigation.favoriteClosetID == closet.id
        return HStack(spacing: 6) {
            // A sibling button rather than one nested inside the row button:
            // nesting them would make the star's tap also trigger navigation.
            Button {
                navigation.toggleFavorite(closet.id)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(isFavorite ? Color(red: 0.85, green: 0.65, blue: 0.13) : Theme.Color.tertiaryText)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                path = [closet.id]
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(closet.name)
                            .font(Theme.Font.headline(18))
                            .foregroundStyle(Theme.Color.primaryText)
                            .lineLimit(1)

                        Text(subtitle(for: closet))
                            .font(Theme.Font.body(12.5))
                            .foregroundStyle(Theme.Color.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.tertiaryText.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        // Favorites read subtly warmer and a touch lifted, without changing
        // shape or becoming a visibly different kind of row.
        .background(isFavorite ? Theme.Color.accent.opacity(0.07) : Theme.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: isFavorite ? Theme.Color.accent.opacity(0.12) : .clear, radius: isFavorite ? 5 : 0, y: isFavorite ? 2 : 0)
    }

    private func subtitle(for closet: Closet) -> String {
        let members = viewModel.memberCounts[closet.id] ?? 0
        let pieces = viewModel.pieceCounts[closet.id] ?? 0
        let memberText = "\(members) member\(members == 1 ? "" : "s")"
        let pieceText = "\(pieces) piece\(pieces == 1 ? "" : "s")"
        return "\(memberText) · \(pieceText)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Closets yet")
                .font(Theme.Font.headline(22))
                .foregroundStyle(Theme.Color.primaryText)
            Text("Create one for your group, or join a friend's with their code.")
                .font(Theme.Font.body(14))
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
