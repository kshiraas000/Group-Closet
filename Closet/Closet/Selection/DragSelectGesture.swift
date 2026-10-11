import SwiftUI
import UIKit

/// Each tile's frame in the grid's coordinate space, so a drag location can
/// be mapped back to the tile under the finger.
struct TileFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func reportTileFrame(id: UUID, in space: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: TileFramesKey.self, value: [id: geo.frame(in: .named(space))])
        })
    }
}

/// Pan that only begins when the first motion is mostly horizontal, so
/// vertical drags still scroll the grid (the Photos behaviour).
@available(iOS 18.0, *)
struct DragSelectGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let coordinateSpace: String
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    /// Disabling a recognizer mid-gesture cancels it, which calls onEnded.
    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(context.converter.location(in: .named(coordinateSpace)))
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}

/// Attaches DragSelectGesture on iOS 18+ while select mode is on; a no-op
/// otherwise (tap-to-select still works everywhere).
struct DragSelectModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        // Always the same view structure so toggling select mode doesn't
        // rebuild the grid; the gesture enables/disables itself.
        if #available(iOS 18.0, *) {
            content.gesture(DragSelectGesture(isEnabled: isEnabled, coordinateSpace: "grid", onChanged: onChanged, onEnded: onEnded))
        } else {
            content
        }
    }
}
