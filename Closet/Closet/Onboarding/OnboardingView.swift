import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    let userID: UUID
    let onComplete: () -> Void

    var body: some View {
        Form {
            Section("Your name") {
                TextField("Name", text: $viewModel.name)
                    .font(Theme.Font.body(16))
            }
            Section("Your usual sizes (optional)") {
                TextField("Top", text: $viewModel.topSize)
                    .font(Theme.Font.body(16))
                TextField("Bottom", text: $viewModel.bottomSize)
                    .font(Theme.Font.body(16))
                TextField("Shoe", text: $viewModel.shoeSize)
                    .font(Theme.Font.body(16))
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.body(14))
                    .foregroundStyle(.red)
            }
            Button(viewModel.isSaving ? "Saving..." : "Continue") {
                Task {
                    if await viewModel.save(userID: userID) {
                        onComplete()
                    }
                }
            }
            .font(Theme.Font.body(16, weight: .medium))
            .disabled(viewModel.isSaving)
            .tint(Theme.Color.accent)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Color.background)
    }
}
