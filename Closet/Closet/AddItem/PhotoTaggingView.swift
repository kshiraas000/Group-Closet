import PhotosUI
import SwiftUI

struct PhotoTaggingView: View {
    @Bindable var viewModel: AddItemViewModel
    let startIndex: Int
    let onCancel: () -> Void
    let onFinished: () -> Void

    @State private var currentIndex: Int
    @State private var selectedMorePhotos: [PhotosPickerItem] = []

    init(viewModel: AddItemViewModel, startIndex: Int, onCancel: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.viewModel = viewModel
        self.startIndex = startIndex
        self.onCancel = onCancel
        self.onFinished = onFinished
        _currentIndex = State(initialValue: startIndex)
    }

    private var isLastPiece: Bool {
        currentIndex == viewModel.draftItems.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    thumbnailStrip

                    Image(uiImage: viewModel.draftItems[currentIndex].image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    nameField

                    categorySection

                    detailsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }

            bottomBar
        }
        .background(Theme.Color.background)
        .onChange(of: selectedMorePhotos) { _, newValue in
            Task { await addPhotos(newValue) }
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Cancel", action: onCancel)
                    .font(Theme.Font.body(15))
                    .foregroundStyle(Theme.Color.accent)
                Spacer()
                Text("Piece \(currentIndex + 1) of \(viewModel.draftItems.count)")
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            Text("Tag your pieces")
                .font(Theme.Font.headline(28))
                .foregroundStyle(Theme.Color.primaryText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(viewModel.draftItems.enumerated()), id: \.element.id) { index, draft in
                    Button {
                        currentIndex = index
                    } label: {
                        Image(uiImage: draft.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.Color.accent, lineWidth: index == currentIndex ? 2 : 0)
                            )
                            .overlay(alignment: .topTrailing) {
                                if draft.category != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.Color.accent, Theme.Color.background)
                                        .padding(3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }

                PhotosPicker(selection: $selectedMorePhotos, maxSelectionCount: 20, matching: .images) {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.Color.primaryText.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "plus")
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                }
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Name this piece")
            HStack {
                TextField("e.g. Black slip dress", text: captionBinding)
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.Color.primaryText)
                Text("\(viewModel.draftItems[currentIndex].caption.count)/40")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Theme.Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var captionBinding: Binding<String> {
        Binding(
            get: { viewModel.draftItems[currentIndex].caption },
            set: { viewModel.draftItems[currentIndex].caption = String($0.prefix(40)) }
        )
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Category · Required")
            let columns = [GridItem(.adaptive(minimum: 90))]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ItemCategory.allCases) { category in
                    categoryChip(category)
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Details · Optional")
            VStack(spacing: 0) {
                detailRow(label: "Size", value: $viewModel.draftItems[currentIndex].size)
                Divider().overlay(Theme.Color.divider)
                detailRow(label: "Color", value: $viewModel.draftItems[currentIndex].color)
                Divider().overlay(Theme.Color.divider)
                detailRow(label: "Occasions", value: $viewModel.draftItems[currentIndex].occasionTags, placeholder: "Comma separated")
            }
            .background(Theme.Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func detailRow(label: String, value: Binding<String>, placeholder: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(Theme.Font.body(16))
                .foregroundStyle(Theme.Color.primaryText)
            Spacer()
            TextField(placeholder ?? label, text: value)
                .font(Theme.Font.body(16))
                .foregroundStyle(Theme.Color.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button(isLastPiece ? "Continue" : "Next piece") {
                advance()
            }
            .font(Theme.Font.body(16, weight: .medium))
            .foregroundStyle(Theme.Color.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(viewModel.draftItems[currentIndex].category == nil)
            .opacity(viewModel.draftItems[currentIndex].category == nil ? 0.5 : 1)

            Button("Skip") {
                advance()
            }
            .font(Theme.Font.body(14))
            .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.Color.background)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func categoryChip(_ category: ItemCategory) -> some View {
        let isSelected = viewModel.draftItems[currentIndex].category == category
        return Button {
            viewModel.selectCategory(category, forItemAt: currentIndex)
        } label: {
            Text(category.rawValue)
                .font(Theme.Font.body(14, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Theme.Color.background : Theme.Color.primaryText.opacity(0.75))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Theme.Color.accent : Theme.Color.primaryText.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.Font.body(12, weight: .medium))
            .foregroundStyle(Theme.Color.secondaryText)
            .tracking(0.4)
    }

    private func advance() {
        if isLastPiece {
            onFinished()
        } else {
            currentIndex += 1
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { return }
        viewModel.addImages(images)
        selectedMorePhotos = []
    }
}
