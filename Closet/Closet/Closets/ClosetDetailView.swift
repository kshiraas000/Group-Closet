import SwiftUI

private struct ItemDetailContext: Identifiable {
    let id = UUID()
    let items: [BrowseItem]
    let startIndex: Int
}

struct ClosetDetailView: View {
    @State private var viewModel = ClosetDetailViewModel()
    @State private var showingLeaveConfirmation = false
    @State private var showingAddItem = false
    @State private var showingFilters = false
    @State private var detailContext: ItemDetailContext?
    @Environment(\.dismiss) private var dismiss
    let closet: Closet
    let userID: UUID
    let onLeft: () -> Void

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        List {
            Section("Members") {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    ForEach(viewModel.members) { member in
                        Text(member.name)
                            .font(Theme.Font.body(16))
                            .foregroundStyle(Theme.Color.primaryText)
                    }
                }
            }
            .listRowBackground(Theme.Color.background)

            Section("Items") {
                CategoryChipsRow(selectedCategory: $viewModel.filters.category) {
                    showingFilters = true
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Theme.Color.background)

                if viewModel.filteredItems.isEmpty {
                    Text(viewModel.items.isEmpty ? "No items yet" : "No items match your filters")
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .listRowBackground(Theme.Color.background)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        ForEach(viewModel.filteredItems) { browseItem in
                            Button {
                                openDetail(for: browseItem)
                            } label: {
                                itemCell(browseItem)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Theme.Color.background)
                }
            }

            Section {
                ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)") {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
                .font(Theme.Font.body(16))
                .tint(Theme.Color.accent)
            }
            .listRowBackground(Theme.Color.background)

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                }
                .listRowBackground(Theme.Color.background)
            }

            Section {
                Button("Leave Closet", role: .destructive) {
                    showingLeaveConfirmation = true
                }
                .font(Theme.Font.body(16))
            }
            .listRowBackground(Theme.Color.background)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Color.background)
        .searchable(text: $viewModel.filters.searchText)
        .navigationTitle(closet.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(Theme.Color.accent)
            }
        }
        .task {
            await viewModel.load(closetID: closet.id)
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(closetID: closet.id, userID: userID) {
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
        .fullScreenCover(item: $detailContext) { context in
            ItemDetailView(
                items: context.items,
                startIndex: context.startIndex,
                members: viewModel.members,
                userID: userID,
                onShareChanged: { Task { await viewModel.load(closetID: closet.id) } },
                onBlocked: { Task { await viewModel.load(closetID: closet.id) } }
            )
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
        return AsyncImage(url: browseItem.signedURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.Color.accent.opacity(0.12))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .bottomLeading) {
            OwnerBadge(profile: owner, signedURL: owner.flatMap { viewModel.memberPhotoURLs[$0.id] })
                .padding(6)
        }
    }
}
