import SwiftUI
import UIKit

/// A compact bottom sheet with two fixed sizes — no preview card yet, or
/// with one — switched by `selectedDetent` rather than measured, which is
/// the supported, reliable way to resize a sheet between a few known states.
struct JoinClosetView: View {
    private static let collapsedDetent: PresentationDetent = .height(260)
    private static let expandedDetent: PresentationDetent = .height(380)

    @State private var viewModel = JoinClosetViewModel()
    @FocusState private var isCodeFocused: Bool
    @State private var selectedDetent: PresentationDetent = JoinClosetView.collapsedDetent
    @State private var clipboardCode: String?
    @Environment(\.dismiss) private var dismiss
    let onJoined: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Join a Closet")
                .font(Theme.Font.headline(20))
                .foregroundStyle(Theme.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("Invite code", text: codeBinding)
                        .font(Theme.Font.body(17, weight: .medium))
                        .foregroundStyle(Theme.Color.primaryText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($isCodeFocused)

                    if viewModel.isLoadingPreview {
                        ProgressView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Theme.Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let clipboardCode, clipboardCode != viewModel.inviteCode {
                    Button {
                        viewModel.inviteCode = clipboardCode
                        viewModel.codeChanged()
                    } label: {
                        Label("Paste Code", systemImage: "doc.on.clipboard")
                            .font(Theme.Font.body(13, weight: .medium))
                    }
                    .foregroundStyle(Theme.Color.accent)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(13))
                        .foregroundStyle(.red)
                }
            }

            if let preview = viewModel.preview {
                previewCard(preview)
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.Color.primaryText.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                joinButton
            }
        }
        .padding(20)
        .padding(.bottom, 4)
        .background(Theme.Color.background)
        .presentationDetents([Self.collapsedDetent, Self.expandedDetent], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            isCodeFocused = true
            clipboardCode = Self.validClipboardCode()
        }
        .onChange(of: viewModel.preview?.closetID) { _, closetID in
            selectedDetent = closetID == nil ? Self.collapsedDetent : Self.expandedDetent
        }
    }

    /// Filters to letters/digits, upper-cases, and caps at codeLength —
    /// matching how the server normalizes a code — so what's on screen is
    /// always exactly what gets submitted.
    private var codeBinding: Binding<String> {
        Binding(
            get: { viewModel.inviteCode },
            set: { newValue in
                let filtered = String(
                    newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(JoinClosetViewModel.codeLength)
                )
                guard filtered != viewModel.inviteCode else { return }
                viewModel.inviteCode = filtered
                viewModel.codeChanged()
            }
        )
    }

    private func previewCard(_ preview: ClosetPreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preview.name)
                .font(Theme.Font.headline(17))
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(1)
            Text("\(preview.memberCount) member\(preview.memberCount == 1 ? "" : "s") · \(preview.pieceCount) piece\(preview.pieceCount == 1 ? "" : "s")")
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.secondaryText)
            if preview.alreadyMember {
                Text("You're already in this closet")
                    .font(Theme.Font.body(12.5, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var joinButton: some View {
        Button {
            Task {
                if let closetID = await viewModel.join() {
                    dismiss()
                    onJoined(closetID)
                }
            }
        } label: {
            Text(joinButtonTitle)
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(Theme.Color.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .background(viewModel.preview == nil ? Theme.Color.accent.opacity(0.4) : Theme.Color.accent)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(viewModel.preview == nil || viewModel.isJoining)
    }

    private var joinButtonTitle: String {
        if viewModel.isJoining { return "Joining..." }
        return viewModel.preview?.alreadyMember == true ? "Open Closet" : "Join Closet"
    }

    /// hasStrings is checked first so an empty pasteboard never triggers a
    /// system clipboard-read notification; a non-empty one is still read to
    /// check validity, the same as iOS's own paste-suggestion UI does.
    private static func validClipboardCode() -> String? {
        guard UIPasteboard.general.hasStrings, let raw = UIPasteboard.general.string else { return nil }
        let filtered = String(raw.uppercased().filter { $0.isLetter || $0.isNumber })
        return filtered.count == JoinClosetViewModel.codeLength ? filtered : nil
    }
}
