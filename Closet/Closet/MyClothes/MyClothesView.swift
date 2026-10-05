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
    let userID: UUID

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
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
            .background(Theme.Color.background)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.load(userID: userID)
            }
            .refreshable {
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
    }
}
