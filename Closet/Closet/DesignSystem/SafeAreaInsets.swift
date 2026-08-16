import UIKit

// fullScreenCover-presented custom-chrome roots (no NavigationStack) don't
// reliably report their real top safe area via SwiftUI's own safeAreaInset
// API on this SDK — content ends up flush with the physical top edge,
// under the status bar/Dynamic Island. Reading UIKit's window inset
// directly sidesteps that and is always correct.
extension UIApplication {
    static var keyWindowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
}
