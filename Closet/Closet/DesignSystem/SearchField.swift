import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Color.tertiaryText)
            TextField(placeholder, text: $text)
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.Color.primaryText)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Color.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.Color.primaryText.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
