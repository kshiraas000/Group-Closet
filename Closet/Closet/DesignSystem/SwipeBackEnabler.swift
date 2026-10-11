import SwiftUI

// .toolbar(.hidden, for: .navigationBar) also disables the interactive
// edge-swipe-to-pop gesture as a side effect, since UIKit ties the gesture's
// delegate to the navigation bar's back item. Re-enabling it here restores
// swipe-back on custom-chrome screens without bringing the system bar back.
//
// A real always-true delegate is used rather than nil: nilling the
// recognizer's delegate leaves it in an inconsistent state after the first
// pop (no target to consult), and a second swipe on the popped-to view can
// stop responding until another push/pop. Returning true unconditionally
// mirrors the system's own default behavior when a back button is present.
final class SwipeBackEnablerCoordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> SwipeBackEnablerCoordinator {
        SwipeBackEnablerCoordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.delegate = context.coordinator
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
