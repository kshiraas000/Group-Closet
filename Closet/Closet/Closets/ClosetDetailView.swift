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
    @State private var detailContext: ItemDetailContext?
    @Environment(\.dismiss) private var dismiss
    let closet: Closet
    let userID: UUID
    let onLeft: () -> Void

    private let gridColumns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        List {
            Section("Members") {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    ForEach(viewModel.members) { member in
                        Text(member.name)
                    }
                }
            }
            Section("Items") {
                filterChipsRow

                if viewModel.filteredItems.isEmpty {
                    Text(viewModel.items.isEmpty ? "No items yet" : "No items match your filters")
                        .foregroundStyle(.secondary)
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
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)") {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section {
                Button("Leave Closet", role: .destructive) {
                    showingLeaveConfirmation = true
                }
            }
        }
        .searchable(text: $viewModel.filters.searchText)
        .navigationTitle(closet.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
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

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All Categories") { viewModel.filters.category = nil }
                    ForEach(ItemCategory.allCases) { category in
                        Button(category.rawValue) { viewModel.filters.category = category }
                    }
                } label: {
                    chipLabel("Category", value: viewModel.filters.category?.rawValue)
                }

                Menu {
                    Button("Everyone") { viewModel.filters.ownerID = nil }
                    ForEach(viewModel.members) { member in
                        Button(member.name) { viewModel.filters.ownerID = member.id }
                    }
                } label: {
                    chipLabel("Person", value: viewModel.members.first { $0.id == viewModel.filters.ownerID }?.name)
                }

                if !viewModel.availableSizes.isEmpty {
                    Menu {
                        Button("Any Size") { viewModel.filters.size = nil }
                        ForEach(viewModel.availableSizes, id: \.self) { size in
                            Button(size) { viewModel.filters.size = size }
                        }
                    } label: {
                        chipLabel("Size", value: viewModel.filters.size)
                    }
                }

                if !viewModel.availableColors.isEmpty {
                    Menu {
                        Button("Any Color") { viewModel.filters.color = nil }
                        ForEach(viewModel.availableColors, id: \.self) { color in
                            Button(color) { viewModel.filters.color = color }
                        }
                    } label: {
                        chipLabel("Color", value: viewModel.filters.color)
                    }
                }

                if !viewModel.availableOccasions.isEmpty {
                    Menu {
                        Button("Any Occasion") { viewModel.filters.occasion = nil }
                        ForEach(viewModel.availableOccasions, id: \.self) { occasion in
                            Button(occasion) { viewModel.filters.occasion = occasion }
                        }
                    } label: {
                        chipLabel("Occasion", value: viewModel.filters.occasion)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func chipLabel(_ title: String, value: String?) -> some View {
        Text(value ?? title)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(value == nil ? Color.secondary.opacity(0.15) : Color.blue.opacity(0.2))
            .clipShape(Capsule())
    }

    private func itemCell(_ browseItem: BrowseItem) -> some View {
        AsyncImage(url: browseItem.signedURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(height: 110)
        .clipped()
    }
}
