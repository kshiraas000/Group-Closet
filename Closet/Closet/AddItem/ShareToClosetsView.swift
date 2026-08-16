import SwiftUI
import PostgREST
import Supabase

struct ShareToClosetsView: View {
    @Bindable var viewModel: AddItemViewModel
    @State private var otherClosets: [Closet] = []
    @State private var isLoadingClosets = true
    @State private var closetsErrorMessage: String?
    let currentClosetID: UUID
    let currentClosetName: String
    let ownerID: UUID
    let onBack: () -> Void
    let onEditPiece: (Int) -> Void
    let onDone: () -> Void

    private var hasStartedSaving: Bool {
        viewModel.draftItems.contains { $0.saveState != .pending }
    }

    private var allSaved: Bool {
        !viewModel.draftItems.isEmpty && viewModel.draftItems.allSatisfy { $0.saveState == .saved }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !hasStartedSaving {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("Also share to")
                            card {
                                if isLoadingClosets {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                } else if let closetsErrorMessage {
                                    Text(closetsErrorMessage)
                                        .font(Theme.Font.body(14))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 13)
                                } else if otherClosets.isEmpty {
                                    Text("You're not in any other Closets")
                                        .font(Theme.Font.body(14))
                                        .foregroundStyle(Theme.Color.secondaryText)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 13)
                                } else {
                                    ForEach(Array(otherClosets.enumerated()), id: \.element.id) { index, closet in
                                        if index > 0 {
                                            Divider().overlay(Theme.Color.divider)
                                        }
                                        Button {
                                            toggle(closet.id)
                                        } label: {
                                            HStack {
                                                Text(closet.name)
                                                    .font(Theme.Font.body(16))
                                                    .foregroundStyle(Theme.Color.primaryText)
                                                Spacer()
                                                if viewModel.shareToClosetIDs.contains(closet.id) {
                                                    Image(systemName: "checkmark")
                                                        .foregroundStyle(Theme.Color.accent)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 13)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Pieces")
                        card {
                            ForEach(Array(viewModel.draftItems.enumerated()), id: \.element.id) { index, draft in
                                if index > 0 {
                                    Divider().overlay(Theme.Color.divider)
                                }
                                pieceRow(index: index, draft: draft)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            bottomBar
        }
        .background(Theme.Color.background)
        .task { await loadOtherClosets() }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Back")
                    }
                }
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.Color.accent)
                .disabled(hasStartedSaving)
                .opacity(hasStartedSaving ? 0.4 : 1)
                Spacer()
                if !hasStartedSaving {
                    Text("Step 2 of 2")
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Color.tertiaryText)
                } else if !allSaved {
                    Button("Close") { onDone() }
                        .font(Theme.Font.body(15))
                        .foregroundStyle(Theme.Color.accent)
                }
            }
            Text(hasStartedSaving ? "Saving..." : "Review & save")
                .font(Theme.Font.headline(28))
                .foregroundStyle(Theme.Color.primaryText)
            if !hasStartedSaving {
                Text("\(viewModel.draftItems.count) piece\(viewModel.draftItems.count == 1 ? "" : "s") going into \(currentClosetName)")
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func pieceRow(index: Int, draft: DraftItem) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: draft.image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.caption.isEmpty ? "Untitled piece" : draft.caption)
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.Color.primaryText)
                if let category = draft.category {
                    let details = [category.rawValue, draft.size, draft.color]
                        .filter { !$0.isEmpty }
                    Text(details.joined(separator: " · "))
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.secondaryText)
                } else {
                    Text("Needs a category")
                        .font(Theme.Font.body(12))
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if hasStartedSaving {
                itemStatusView(index: index, state: draft.saveState)
            } else if draft.category == nil {
                Button("Fix") { onEditPiece(index) }
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(.red)
            } else {
                Button("Edit") { onEditPiece(index) }
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var bottomBar: some View {
        Group {
            if allSaved {
                Button("View in closet") { onDone() }
                    .font(Theme.Font.body(16, weight: .medium))
                    .foregroundStyle(Theme.Color.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if !hasStartedSaving {
                Button("Save \(viewModel.draftItems.count) piece\(viewModel.draftItems.count == 1 ? "" : "s")") {
                    Task { await viewModel.saveAll(currentClosetID: currentClosetID, ownerID: ownerID) }
                }
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(Theme.Color.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.Font.body(12, weight: .medium))
            .foregroundStyle(Theme.Color.secondaryText)
            .tracking(0.4)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Theme.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Color.accent)
        case .failed(let message) where message == "Missing category":
            Button("Fix") { onEditPiece(index) }
                .font(Theme.Font.body(14, weight: .medium))
                .foregroundStyle(.red)
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
