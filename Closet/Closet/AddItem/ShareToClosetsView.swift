import SwiftUI
import PostgREST
import Supabase

struct ShareToClosetsView: View {
    @Bindable var viewModel: AddItemViewModel
    @State private var otherClosets: [Closet] = []
    @State private var isLoadingClosets = true
    @State private var closetsErrorMessage: String?
    let currentClosetID: UUID
    let ownerID: UUID
    let onDone: () -> Void

    private var isSaving: Bool {
        viewModel.draftItems.contains { $0.saveState == .saving }
    }

    private var allSaved: Bool {
        !viewModel.draftItems.isEmpty && viewModel.draftItems.allSatisfy { $0.saveState == .saved }
    }

    var body: some View {
        VStack {
            List {
                Section("Also share to") {
                    if isLoadingClosets {
                        ProgressView()
                    } else if let closetsErrorMessage {
                        Text(closetsErrorMessage)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(.red)
                    } else if otherClosets.isEmpty {
                        Text("You're not in any other Closets")
                            .font(Theme.Font.body(14))
                            .foregroundStyle(Theme.Color.secondaryText)
                    } else {
                        ForEach(otherClosets) { closet in
                            Button {
                                toggle(closet.id)
                            } label: {
                                HStack {
                                    Text(closet.name)
                                        .font(Theme.Font.body(16))
                                    Spacer()
                                    if viewModel.shareToClosetIDs.contains(closet.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.Color.accent)
                                    }
                                }
                            }
                            .foregroundStyle(Theme.Color.primaryText)
                        }
                    }
                }
                .listRowBackground(Theme.Color.background)

                Section("Items") {
                    ForEach(Array(viewModel.draftItems.enumerated()), id: \.element.id) { index, draft in
                        HStack {
                            Text(draft.category?.rawValue ?? "Untagged")
                                .font(Theme.Font.body(16))
                                .foregroundStyle(Theme.Color.primaryText)
                            Spacer()
                            itemStatusView(index: index, state: draft.saveState)
                        }
                    }
                }
                .listRowBackground(Theme.Color.background)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)

            if allSaved {
                Button("Done") { onDone() }
                    .font(Theme.Font.body(16, weight: .medium))
                    .tint(Theme.Color.accent)
                    .padding()
            } else {
                Button(isSaving ? "Saving..." : "Save") {
                    Task { await viewModel.saveAll(currentClosetID: currentClosetID, ownerID: ownerID) }
                }
                .font(Theme.Font.body(16, weight: .medium))
                .disabled(isSaving)
                .tint(Theme.Color.accent)
                .padding()
            }
        }
        .background(Theme.Color.background)
        .task { await loadOtherClosets() }
    }

    private func toggle(_ closetID: UUID) {
        if viewModel.shareToClosetIDs.contains(closetID) {
            viewModel.shareToClosetIDs.remove(closetID)
        } else {
            viewModel.shareToClosetIDs.insert(closetID)
        }
    }

    private func loadOtherClosets() async {
        isLoadingClosets = true
        closetsErrorMessage = nil
        defer { isLoadingClosets = false }
        do {
            let all: [Closet] = try await SupabaseService.shared
                .from("closets")
                .select()
                .execute()
                .value
            otherClosets = all.filter { $0.id != currentClosetID }
        } catch {
            closetsErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func itemStatusView(index: Int, state: SaveState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(Theme.Color.tertiaryText)
        case .saving:
            ProgressView()
        case .saved:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Button {
                Task { await viewModel.save(itemAt: index, currentClosetID: currentClosetID, ownerID: ownerID) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise.circle.fill")
            }
            .foregroundStyle(.red)
            .help(message)
        }
    }
}
