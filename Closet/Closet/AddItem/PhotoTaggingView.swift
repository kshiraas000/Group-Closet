import SwiftUI

struct PhotoTaggingView: View {
    @Bindable var viewModel: AddItemViewModel
    @State private var currentIndex = 0
    let onFinished: () -> Void

    var body: some View {
        VStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.draftItems.enumerated()), id: \.element.id) { index, _ in
                    tagForm(index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .background(Theme.Color.background)

            Button(currentIndex == viewModel.draftItems.count - 1 ? "Continue" : "Next") {
                if currentIndex < viewModel.draftItems.count - 1 {
                    currentIndex += 1
                } else {
                    onFinished()
                }
            }
            .font(Theme.Font.body(16, weight: .medium))
            .disabled(!viewModel.draftItems.indices.contains(currentIndex) || viewModel.draftItems[currentIndex].category == nil)
            .tint(Theme.Color.accent)
            .padding()
        }
        .background(Theme.Color.background)
    }

    private func tagForm(index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(uiImage: viewModel.draftItems[index].image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Category")
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(Theme.Color.primaryText)
                let columns = [GridItem(.adaptive(minimum: 90))]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ItemCategory.allCases) { category in
                        Button(category.rawValue) {
                            viewModel.selectCategory(category, forItemAt: index)
                        }
                        .font(Theme.Font.body(14))
                        .buttonStyle(.bordered)
                        .tint(viewModel.draftItems[index].category == category ? Theme.Color.accent : Theme.Color.tertiaryText)
                    }
                }

                DisclosureGroup("More details (optional)") {
                    VStack(spacing: 8) {
                        TextField("Size", text: $viewModel.draftItems[index].size)
                            .textFieldStyle(.roundedBorder)
                        TextField("Color", text: $viewModel.draftItems[index].color)
                            .textFieldStyle(.roundedBorder)
                        TextField("Occasions (comma separated)", text: $viewModel.draftItems[index].occasionTags)
                            .textFieldStyle(.roundedBorder)
                        TextField("Caption", text: $viewModel.draftItems[index].caption)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.Color.primaryText)
                .tint(Theme.Color.accent)
            }
            .padding()
        }
        .background(Theme.Color.background)
    }
}
