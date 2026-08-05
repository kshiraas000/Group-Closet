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

            Button(currentIndex == viewModel.draftItems.count - 1 ? "Continue" : "Next") {
                if currentIndex < viewModel.draftItems.count - 1 {
                    currentIndex += 1
                } else {
                    onFinished()
                }
            }
            .disabled(!viewModel.draftItems.indices.contains(currentIndex) || viewModel.draftItems[currentIndex].category == nil)
            .padding()
        }
    }

    private func tagForm(index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(uiImage: viewModel.draftItems[index].image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)

                Text("Category").font(.headline)
                let columns = [GridItem(.adaptive(minimum: 90))]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ItemCategory.allCases) { category in
                        Button(category.rawValue) {
                            viewModel.selectCategory(category, forItemAt: index)
                        }
                        .buttonStyle(.bordered)
                        .tint(viewModel.draftItems[index].category == category ? .blue : .gray)
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
            }
            .padding()
        }
    }
}
