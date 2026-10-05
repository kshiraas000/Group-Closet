import SwiftUI

private struct ItemDetailContext: Identifiable {
    let id = UUID()
    let items: [BrowseItem]
    let startIndex: Int
}

struct MyClothesView: View {
    @State private var viewModel = MyClothesViewModel()
    @State private var detailContext: ItemDetailContext?
    @State private var showingFilters = false
    @State private var selection = GridSelection()
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingBulkEdit = false
    @State private var showingAddToClosetPicker = false
    @State private var showingRemoveFromClosetPicker = false
    @State private var showingBulkActionError = false
    let userID: UUID

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selection.isActive {
                    SelectionTopBar(count: selection.count) { selection.end() }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        SearchField(text: $viewModel.filters.searchText, placeholder: "Search your clothes")

                        CategoryChipsRow(selectedCategories: $viewModel.filters.categories) {
                            showingFilters = true
                        }

                        ActiveFiltersRow(filters: $viewModel.filters, ownerName: nil)

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
                                        .onTapGesture { tileTapped(browseItem) }
                                        .onLongPressGesture(minimumDuration: 0.35) {
                                            if !selection.isActive { selection.begin(with: browseItem.id) }
                                        }
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction(named: "Select") {
                                            if !selection.isActive { selection.begin(with: browseItem.id) }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await viewModel.load(userID: userID)
                }

                if selection.isActive {
                    SelectionActionBar(
                        count: selection.count,
                        removeTitle: "Remove from…",
                        onAdd: { showingAddToClosetPicker = true },
                        onRemove: { showingRemoveFromClosetPicker = true },
                        onEdit: { showingBulkEdit = true },
                        onDelete: { showingBulkDeleteConfirmation = true }
                    )
                }
            }
            .background(Theme.Color.background)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.load(userID: userID)
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(
                    filters: $viewModel.filters,
                    members: nil,
                    availableSizes: viewModel.availableSizes,
                    availableColors: viewModel.availableColors,
                    availableOccasions: viewModel.availableOccasions
                )
            }
            .sheet(isPresented: $showingAddToClosetPicker) {
                ClosetPickerSheet(title: "Add to Closet", excludingClosetID: nil) { target in
                    let ids = Array(selection.selectedIDs)
                    Task { await runBulk { try await BulkItemActions.addShares(itemIDs: ids, closetID: target.id) } }
                }
            }
            .sheet(isPresented: $showingRemoveFromClosetPicker) {
                ClosetPickerSheet(title: "Remove from Closet", excludingClosetID: nil) { target in
                    let ids = Array(selection.selectedIDs)
                    Task { await runBulk { try await BulkItemActions.removeShares(itemIDs: ids, closetID: target.id) } }
                }
            }
            .sheet(isPresented: $showingBulkEdit) {
                BulkEditView(count: selection.count) { edit in
                    let items = selectedItems.map(\.item)
                    do {
                        try await BulkItemActions.apply(edit, to: items)
                        selection.end()
                        await viewModel.load(userID: userID)
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
            .fullScreenCover(item: $detailContext) { context in
                ItemDetailView(
                    items: context.items,
                    startIndex: context.startIndex,
                    members: [viewModel.myProfile].compactMap { $0 },
                    memberPhotoURLs: viewModel.memberPhotoURLs,
                    userID: userID,
                    onItemChanged: { Task { await viewModel.load(userID: userID) } }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("My Clothes")
                .font(Theme.Font.headline(32))
                .foregroundStyle(Theme.Color.primaryText)

            if !viewModel.isLoading {
                let count = viewModel.items.count
                Text("\(count) piece\(count == 1 ? "" : "s")")
                    .font(Theme.Font.body(12.5))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
    }

    private func openDetail(for browseItem: BrowseItem) {
        let snapshot = viewModel.filteredItems
        if let index = snapshot.firstIndex(where: { $0.id == browseItem.id }) {
            detailContext = ItemDetailContext(items: snapshot, startIndex: index)
        }
    }

    private func tileTapped(_ browseItem: BrowseItem) {
        if selection.isActive {
            selection.toggle(browseItem.id)
        } else {
            openDetail(for: browseItem)
        }
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
        await viewModel.load(userID: userID)
    }

    private func itemCell(_ browseItem: BrowseItem) -> some View {
        // Color.clear takes the grid's proposed width and .fit turns it into a
        // square. The image fills that square as an overlay and .clipped() cuts
        // the overflow. Sizing the AsyncImage itself with .aspectRatio(.fill)
        // let tall photos report a frame bigger than the cell, so they spilled
        // over their neighbours.
        Color.clear
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
            .overlay(alignment: .bottomTrailing) {
                if selection.isActive {
                    SelectionCheckmark(isSelected: selection.selectedIDs.contains(browseItem.id))
                }
            }
    }
}
