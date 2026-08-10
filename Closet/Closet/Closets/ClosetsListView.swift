import SwiftUI

struct ClosetsListView: View {
    @State private var viewModel = ClosetsViewModel()
    @State private var showingCreate = false
    @State private var showingJoin = false
    let userID: UUID

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                } else if viewModel.closets.isEmpty {
                    emptyState
                } else {
                    List(viewModel.closets) { closet in
                        NavigationLink {
                            ClosetDetailView(closet: closet, userID: userID) {
                                Task { await viewModel.loadClosets() }
                            }
                        } label: {
                            Text(closet.name)
                                .font(Theme.Font.headline(20))
                                .foregroundStyle(Theme.Color.primaryText)
                        }
                        .listRowBackground(Theme.Color.background)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.Color.background)
                }
            }
            .background(Theme.Color.background)
            .navigationTitle("Closets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create a Closet") { showingCreate = true }
                        Button("Join with invite code") { showingJoin = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Theme.Color.accent)
                }
            }
            .task { await viewModel.loadClosets() }
            .sheet(isPresented: $showingCreate) {
                CreateClosetView {
                    Task { await viewModel.loadClosets() }
                }
            }
            .sheet(isPresented: $showingJoin) {
                JoinClosetView {
                    Task { await viewModel.loadClosets() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No Closets yet")
                .font(Theme.Font.headline(22))
                .foregroundStyle(Theme.Color.primaryText)
            Button("Create a Closet") { showingCreate = true }
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Button("Have an invite link? Paste it") { showingJoin = true }
                .font(Theme.Font.body(16))
                .foregroundStyle(Theme.Color.accent)
        }
    }
}
