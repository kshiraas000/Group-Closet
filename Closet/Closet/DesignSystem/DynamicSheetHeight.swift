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
        // fixedSize first: without it, the GeometryReader below measures
        // whatever height the sheet currently proposes — which starts at
        // this same binding's initial value. That's a deadlock: a tiny
        // starting height gets "measured" right back as tiny, and the sheet
        // never grows. fixedSize makes this view take its own ideal height
        // regardless of what's proposed, so the real content height is what
        // gets measured and fed back.
        fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SheetHeightKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(SheetHeightKey.self) { height.wrappedValue = $0 }
    }
}
