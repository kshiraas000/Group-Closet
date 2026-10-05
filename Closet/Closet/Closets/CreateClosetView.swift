import SwiftUI

/// A compact bottom sheet, not a full-screen Form — the whole flow is one
/// field. Sizes itself to its content via reportSheetHeight rather than a
/// fixed or .medium detent.
struct CreateClosetView: View {
    @State private var viewModel = CreateClosetViewModel()
    @FocusState private var isNameFocused: Bool
    @State private var sheetHeight: CGFloat = 1
    @Environment(\.dismiss) private var dismiss
    let onCreated: (UUID) -> Void

    private var trimmedName: String {
        viewModel.name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Closet")
                .font(Theme.Font.headline(20))
                .foregroundStyle(Theme.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .center)

            // Just the name field for now — room here for an optional group
            // picture (photo, initials, or emoji) beside it later.
            TextField("Closet name", text: $viewModel.name)
                .font(Theme.Font.body(17))
                .foregroundStyle(Theme.Color.primaryText)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit(create)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Theme.Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.Color.primaryText.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(action: create) {
                    Text(viewModel.isSaving ? "Creating..." : "Create")
                        .font(Theme.Font.body(16, weight: .medium))
                        .foregroundStyle(Theme.Color.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .background(trimmedName.isEmpty ? Theme.Color.accent.opacity(0.4) : Theme.Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(trimmedName.isEmpty || viewModel.isSaving)
            }
        }
        .padding(20)
        .padding(.bottom, 4)
        .background(Theme.Color.background)
        .reportSheetHeight(to: $sheetHeight)
        .presentationDetents([.height(max(sheetHeight, 1))])
        .presentationDragIndicator(.visible)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        guard !trimmedName.isEmpty, !viewModel.isSaving else { return }
        Task {
            if let closet = await viewModel.create() {
                dismiss()
                onCreated(closet.id)
            }
        }
    }
}
