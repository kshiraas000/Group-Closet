import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    let userID: UUID
    let onComplete: () -> Void

    var body: some View {
        Form {
            Section("Your name") {
                TextField("Name", text: $viewModel.name)
            }
            Section("Your usual sizes (optional)") {
                TextField("Top", text: $viewModel.topSize)
                TextField("Bottom", text: $viewModel.bottomSize)
                TextField("Shoe", text: $viewModel.shoeSize)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Button(viewModel.isSaving ? "Saving..." : "Continue") {
                Task {
                    if await viewModel.save(userID: userID) {
                        onComplete()
                    }
                }
            }
            .disabled(viewModel.isSaving)
        }
    }
}
