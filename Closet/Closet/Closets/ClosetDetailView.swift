import SwiftUI

private struct ItemDetailContext: Identifiable {
    let id = UUID()
    let items: [BrowseItem]
    let startIndex: Int
}

struct ClosetDetailView: View {
    @State private var viewModel = ClosetDetailViewModel()
    @State private var showingLeaveConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingAddItem = false
    @State private var showingFilters = false
    @State private var showingMembers = false
    @State private var detailContext: ItemDetailContext?
    @State private var selection = GridSelection()
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingBulkEdit = false
    @State private var showingAddToClosetPicker = false
    @State private var showingBulkActionError = false
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var dragAnchorID: UUID?
    @Environment(\.dismiss) private var dismiss
    let closet: Closet
    let userID: UUID
    let onLeft: () -> Void

    /// Mirrors the DELETE policy on public.closets: the creator, or any member
    /// once the creator has deleted their account and created_by went null.
    private var canDeleteCloset: Bool {
        closet.createdBy == userID || closet.createdBy == nil
    }

    /// Leaving is the same DELETE either way, but for the last member out the
    /// trigger takes the closet with them, so the warning has to say so.
    private var isLastMember: Bool {
        viewModel.members.count <= 1
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if selection.isActive {
                SelectionTopBar(count: selection.count) { selection.end() }
            } else {
                topBar
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    SearchField(text: $viewModel.filters.searchText, placeholder: "Search this closet")

                    CategoryChipsRow(selectedCategories: $viewModel.filters.categories) {
                        showingFilters = true
                    }

                    ActiveFiltersRow(filters: $viewModel.filters, ownerName: selectedOwnerName)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(.red)
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if viewModel.filteredItems.isEmpty {
                        Text(viewModel.items.isEmpty ? "No items yet" : "No items match your filters")
                            .font(Theme.Font.body(14))
                            .foregroundStyle(Theme.Color.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 2) {
                            ForEach(viewModel.filteredItems) { browseItem in
                                // Tap and long-press as separate gestures, not a
                                // Button: a Button also fires on release after a
                                // long hold, un-selecting the tile it just selected.
                                itemCell(browseItem)
                                    .reportTileFrame(id: browseItem.id, in: "grid")
                                    .onTapGesture { tileTapped(browseItem) }
                                    .onLongPressGesture(minimumDuration: 0.35) {
                                        if !selection.isActive, isOwned(browseItem) {
                                            selection.begin(with: browseItem.id)
                                        }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction(named: "Select") {
                                        if !selection.isActive, isOwned(browseItem) {
                                            selection.begin(with: browseItem.id)
                                        }
                                    }
                            }
                        }
                        .coordinateSpace(.named("grid"))
                        .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
                        .modifier(DragSelectModifier(
                            isEnabled: selection.isActive,
                            onChanged: dragChanged,
                            onEnded: dragEnded
                        ))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }

            if selection.isActive {
                SelectionActionBar(
                    count: selection.count,
                    removeTitle: "Remove",
                    onAdd: { showingAddToClosetPicker = true },
                    onRemove: { Task { await removeSelectedFromThisCloset() } },
                    onEdit: { showingBulkEdit = true },
                    onDelete: { showingBulkDeleteConfirmation = true }
                )
            }
        }
        .background(Theme.Color.background)
        .background(SwipeBackEnabler())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.load(closetID: closet.id)
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(closetID: closet.id, closetName: closet.name, userID: userID) {
                Task { await viewModel.load(closetID: closet.id) }
            }
        }
        .sheet(isPresented: $showingFilters) {
            FilterSheet(
                filters: $viewModel.filters,
                members: viewModel.members,
                availableSizes: viewModel.availableSizes,
                availableColors: viewModel.availableColors,
                availableOccasions: viewModel.availableOccasions
            )
        }
        .sheet(isPresented: $showingMembers) {
            membersSheet
        }
        .sheet(isPresented: $showingAddToClosetPicker) {
            ClosetPickerSheet(title: "Add to Closet", excludingClosetID: closet.id) { target in
                let ids = Array(selection.selectedIDs)
                Task { await runBulk { try await BulkItemActions.addShares(itemIDs: ids, closetID: target.id) } }
            }
        }
        .sheet(isPresented: $showingBulkEdit) {
            BulkEditView(count: selection.count) { edit in
                let items = selectedItems.map(\.item)
                do {
                    try await BulkItemActions.apply(edit, to: items)
                    selection.end()
                    await viewModel.load(closetID: closet.id)
                    return true
                } catch {
                    return false
                }
            }
        }
        .confirmationDialog(
            "Delete \(selection.count) piece\(selection.count == 1 ? "" : "s")?",
            isPresented: $showingBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let items = selectedItems
                Task { await runBulk { try await BulkItemActions.delete(items) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes them from every closet and can't be undone.")
        }
        .alert("Something went wrong. Please try again.", isPresented: $showingBulkActionError) {
            Button("OK") {}
        }
        .sensoryFeedback(.selection, trigger: selection.selectedIDs)
        .onChange(of: viewModel.filteredItems.map(\.id)) { _, visible in
            selection.retain(Set(visible))
        }
        .confirmationDialog(
            "Leave \(closet.name)?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    if await viewModel.leave(closetID: closet.id, userID: userID) {
                        onLeft()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if isLastMember {
                Text("You're the last member. Leaving will delete \(closet.name) for good, including its invite code.")
            }
        }
        .confirmationDialog(
            "Delete \(closet.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete for Everyone", role: .destructive) {
                Task {
                    if await viewModel.deleteCloset(closetID: closet.id) {
                        onLeft()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the closet for everyone, not just you. Nobody will be able to open it or use the invite code again. Everyone keeps their own clothes in My Clothes.")
        }
        .fullScreenCover(item: $detailContext) { context in
            ItemDetailView(
                items: context.items,
                startIndex: context.startIndex,
                members: viewModel.members,
                memberPhotoURLs: viewModel.memberPhotoURLs,
                userID: userID,
                onShareChanged: { Task { await viewModel.load(closetID: closet.id) } },
                onBlocked: { Task { await viewModel.load(closetID: closet.id) } },
                onItemChanged: { Task { await viewModel.load(closetID: closet.id) } }
            )
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Closets")
                        .font(Theme.Font.body(15))
                }
                .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 20) {
                Menu {
                    Button {
                        showingMembers = true
                    } label: {
                        Label("Members", systemImage: "person.2")
                    }
                    ShareLink(item: ClosetInvite.shareMessage(closetName: closet.name, inviteCode: closet.inviteCode)) {
                        Label("Share Invite", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingLeaveConfirmation = true
                    } label: {
                        Label("Leave Closet", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    if canDeleteCloset {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Closet", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Color.accent)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var selectedOwnerName: String? {
        guard let ownerID = viewModel.filters.ownerID else { return nil }
        return viewModel.members.first { $0.id == ownerID }?.name
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(closet.name)
                .font(Theme.Font.headline(32))
                .foregroundStyle(Theme.Color.primaryText)

            if !viewModel.isLoading {
                Button {
                    showingMembers = true
                } label: {
                    HStack(spacing: 8) {
                        HStack(spacing: -7) {
                            ForEach(viewModel.members.prefix(3)) { member in
                                OwnerBadge(profile: member, signedURL: viewModel.memberPhotoURLs[member.id])
                            }
                        }
                        Text(memberSummaryText)
                            .font(Theme.Font.body(12.5))
                            .foregroundStyle(Theme.Color.secondaryText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var memberSummaryText: String {
        let names = viewModel.members.map(\.name)
        let joinedNames: String
        switch names.count {
        case 0: joinedNames = ""
        case 1: joinedNames = names[0]
        case 2: joinedNames = "\(names[0]) & \(names[1])"
        default: joinedNames = "\(names.dropLast().joined(separator: ", ")) & \(names.last ?? "")"
        }
        let pieceCount = viewModel.items.count
        return "\(joinedNames) · \(pieceCount) piece\(pieceCount == 1 ? "" : "s")"
    }

    private var membersSheet: some View {
        NavigationStack {
            List {
                Section("Members") {
                    ForEach(viewModel.members) { member in
                        HStack(spacing: 10) {
                            OwnerBadge(profile: member, signedURL: viewModel.memberPhotoURLs[member.id], diameter: 30)
                            Text(member.name)
                                .font(Theme.Font.body(16))
                                .foregroundStyle(Theme.Color.primaryText)
                        }
                    }
                }
                .listRowBackground(Theme.Color.background)

                Section {
                    ShareLink(item: ClosetInvite.shareMessage(closetName: closet.name, inviteCode: closet.inviteCode)) {
                        Label("Share Invite", systemImage: "square.and.arrow.up")
                    }
                    .font(Theme.Font.body(16))
                    .tint(Theme.Color.accent)
                }
                .listRowBackground(Theme.Color.background)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingMembers = false }
                        .tint(Theme.Color.accent)
                }
            }
        }
    }

    private func openDetail(for browseItem: BrowseItem) {
        let snapshot = viewModel.filteredItems
        if let index = snapshot.firstIndex(where: { $0.id == browseItem.id }) {
            detailContext = ItemDetailContext(items: snapshot, startIndex: index)
        }
    }

    private func isOwned(_ browseItem: BrowseItem) -> Bool {
        browseItem.item.ownerID == userID
    }

    private func tileTapped(_ browseItem: BrowseItem) {
        if selection.isActive {
            if isOwned(browseItem) { selection.toggle(browseItem.id) }
        } else {
            openDetail(for: browseItem)
        }
    }

    private func dragChanged(_ location: CGPoint) {
        guard let id = tileFrames.first(where: { $0.value.contains(location) })?.key else { return }
        if dragAnchorID == nil {
            guard let tile = viewModel.filteredItems.first(where: { $0.id == id }), isOwned(tile) else { return }
            dragAnchorID = id
            selection.beginDrag(on: id)
        }
        guard let anchor = dragAnchorID else { return }
        let order = viewModel.filteredItems.map(\.id)
        let selectable = Set(viewModel.filteredItems.filter(isOwned).map(\.id))
        selection.updateDrag(covering: GridDragSelect.coveredIDs(order: order, from: anchor, to: id, selectable: selectable))
    }

    private func dragEnded() {
        dragAnchorID = nil
        selection.endDrag()
    }

    private var selectedItems: [BrowseItem] {
        viewModel.items.filter { selection.selectedIDs.contains($0.id) }
    }

    /// Runs a bulk action, then reloads and leaves select mode on success.
    private func runBulk(_ action: () async throws -> Void) async {
        do {
            try await action()
            selection.end()
        } catch {
            showingBulkActionError = true
        }
        await viewModel.load(closetID: closet.id)
    }

    private func removeSelectedFromThisCloset() async {
        let ids = Array(selection.selectedIDs)
        await runBulk { try await BulkItemActions.removeShares(itemIDs: ids, closetID: closet.id) }
    }

    private func itemCell(_ browseItem: BrowseItem) -> some View {
        let owner = viewModel.members.first { $0.id == browseItem.item.ownerID }
        // Color.clear takes the grid's proposed width and .fit turns it into a
        // square. The image fills that square as an overlay and .clipped() cuts
        // the overflow. Sizing the AsyncImage itself with .aspectRatio(.fill)
        // let tall photos report a frame bigger than the cell, so they spilled
        // over their neighbours.
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: browseItem.signedURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Theme.Color.accent.opacity(0.12))
                    }
                }
            }
            .clipped()
            // clipped() only clips drawing, not hit-testing: without this a
            // tall photo's invisible overflow steals taps from the filter chips.
            .contentShape(Rectangle())
            .overlay(alignment: .bottomLeading) {
            OwnerBadge(profile: owner, signedURL: owner.flatMap { viewModel.memberPhotoURLs[$0.id] })
                .padding(6)
        }
            .overlay(alignment: .bottomTrailing) {
                if selection.isActive, isOwned(browseItem) {
                    SelectionCheckmark(isSelected: selection.selectedIDs.contains(browseItem.id))
                }
            }
            // Other people's pieces can't be selected in select mode.
            .opacity(selection.isActive && !isOwned(browseItem) ? 0.35 : 1)
    }
}
