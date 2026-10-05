import SwiftUI

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Measures this view's natural height and writes it to `height`, so a
    /// sheet's `.presentationDetents([.height(height)])` grows or shrinks to
    /// fit its content instead of sitting at a fixed size or `.medium`.
    func reportSheetHeight(to height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: SheetHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(SheetHeightKey.self) { height.wrappedValue = $0 }
    }
}
