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

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    ProgressView()
                        .listRowBackground(Theme.Color.background)
                } else {
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

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                        .listRowBackground(Theme.Color.background)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .searchable(text: $viewModel.filters.searchText)
            .navigationTitle("My Clothes")
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
                    userID: userID
                )
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
        AsyncImage(url: browseItem.signedURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.Color.accent.opacity(0.12))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
