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
            topBar

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
                                Button {
                                    openDetail(for: browseItem)
                                } label: {
                                    itemCell(browseItem)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
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
    }
}
