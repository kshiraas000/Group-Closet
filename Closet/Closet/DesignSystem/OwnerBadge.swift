import SwiftUI

struct OwnerBadge: View {
    let profile: UserProfile?
    let signedURL: URL?
    var diameter: CGFloat = 22
    /// Matches whatever the badge sits on, so overlapping badges look cut out.
    var ringColor: Color = Theme.Color.background

    var body: some View {
        Group {
            if let signedURL {
                AsyncImage(url: signedURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initialCircle
                    }
                }
            } else {
                initialCircle
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(ringColor, lineWidth: 2))
    }

    private var initialCircle: some View {
        Circle()
            .fill(Theme.Color.accent)
            .overlay(
                Text(initial)
                    .font(Theme.Font.body(diameter * 0.46, weight: .medium))
                    .foregroundStyle(Theme.Color.background)
            )
    }

    private var initial: String {
        guard let first = profile?.name.first else { return "?" }
        return String(first).uppercased()
    }
}
