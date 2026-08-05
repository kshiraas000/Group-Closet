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
                    Text(errorMessage).foregroundStyle(.red)
                } else if viewModel.closets.isEmpty {
                    emptyState
                } else {
                    List(viewModel.closets) { closet in
                        NavigationLink(closet.name) {
                            ClosetDetailView(closet: closet, userID: userID) {
                                Task { await viewModel.loadClosets() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Closets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create a Closet") { showingCreate = true }
                        Button("Join with invite code") { showingJoin = true }
                    } label: {
                        Image(systemName: "plus")
                    }
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
                .font(.headline)
            Button("Create a Closet") { showingCreate = true }
            Button("Have an invite link? Paste it") { showingJoin = true }
        }
    }
}
