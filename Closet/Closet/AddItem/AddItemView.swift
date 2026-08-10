import PhotosUI
import SwiftUI

struct AddItemView: View {
    @State private var viewModel = AddItemViewModel()
    @State private var step: Step = .picking
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss
    let closetID: UUID
    let userID: UUID
    let onItemsSaved: () -> Void

    enum Step {
        case picking
        case tagging
        case sharing
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .picking:
                    pickerView
                case .tagging:
                    PhotoTaggingView(viewModel: viewModel) {
                        step = .sharing
                    }
                case .sharing:
                    ShareToClosetsView(
                        viewModel: viewModel,
                        currentClosetID: closetID,
                        ownerID: userID
                    ) {
                        onItemsSaved()
                        dismiss()
                    }
                }
            }
            .background(Theme.Color.background)
            .navigationTitle("Add Items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await viewModel.loadDefaultSizes(userID: userID) }
    }

    private var pickerView: some View {
        VStack(spacing: 24) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
                    .font(Theme.Font.body(16, weight: .medium))
            }
            .tint(Theme.Color.accent)
            .onChange(of: selectedPhotos) { _, newValue in
                Task { await loadImages(from: newValue) }
            }
        }
        .padding()
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { return }
        viewModel.startTagging(images: images)
        step = .tagging
    }
}
