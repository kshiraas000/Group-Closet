import PhotosUI
import SwiftUI

struct AddItemView: View {
    @State private var viewModel = AddItemViewModel()
    @State private var step: Step = .picking
    @State private var taggingStartIndex = 0
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @Environment(\.dismiss) private var dismiss
    let closetID: UUID
    let closetName: String
    let userID: UUID
    let onItemsSaved: () -> Void

    enum Step {
        case picking
        case tagging
        case sharing
    }

    var body: some View {
        Group {
            switch step {
            case .picking:
                VStack(spacing: 0) {
                    header
                    pickerView
                }
            case .tagging:
                PhotoTaggingView(
                    viewModel: viewModel,
                    startIndex: taggingStartIndex,
                    onCancel: { dismiss() },
                    onFinished: { step = .sharing }
                )
            case .sharing:
                ShareToClosetsView(
                    viewModel: viewModel,
                    currentClosetID: closetID,
                    currentClosetName: closetName,
                    ownerID: userID,
                    onBack: {
                        taggingStartIndex = 0
                        step = .tagging
                    },
                    onEditPiece: { index in
                        taggingStartIndex = index
                        step = .tagging
                    },
                    onDone: {
                        onItemsSaved()
                        dismiss()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
        .task { await viewModel.loadDefaultSizes(userID: userID) }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                viewModel.startTagging(images: [image])
                step = .tagging
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(Theme.Font.body(15))
                    .foregroundStyle(Theme.Color.accent)
                Spacer()
            }
            Text("Add Items")
                .font(Theme.Font.headline(32))
                .foregroundStyle(Theme.Color.primaryText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
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

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .font(Theme.Font.body(16, weight: .medium))
                }
                .tint(Theme.Color.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
