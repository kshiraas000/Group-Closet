import SwiftUI

private extension SwiftUI.Color {
    init(light: SwiftUI.Color, dark: SwiftUI.Color) {
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

enum Theme {
    enum Color {
        static let background = SwiftUI.Color(
            light: SwiftUI.Color(red: 0xF7 / 255, green: 0xF6 / 255, blue: 0xF1 / 255),
            dark: SwiftUI.Color(red: 0x1B / 255, green: 0x1D / 255, blue: 0x1A / 255)
        )
        static let primaryText = SwiftUI.Color(
            light: SwiftUI.Color(red: 0x23 / 255, green: 0x28 / 255, blue: 0x23 / 255),
            dark: SwiftUI.Color(red: 0xF2 / 255, green: 0xF1 / 255, blue: 0xEA / 255)
        )
        static let secondaryText = SwiftUI.Color(
            light: SwiftUI.Color(red: 0x6D / 255, green: 0x73 / 255, blue: 0x70 / 255),
            dark: SwiftUI.Color(red: 0xA3 / 255, green: 0xA9 / 255, blue: 0xA0 / 255)
        )
        static let tertiaryText = SwiftUI.Color(
            light: SwiftUI.Color(red: 0x8B / 255, green: 0x91 / 255, blue: 0x8C / 255),
            dark: SwiftUI.Color(red: 0x7D / 255, green: 0x83 / 255, blue: 0x7B / 255)
        )
        static let accent = SwiftUI.Color(
            light: SwiftUI.Color(red: 0x4A / 255, green: 0x5D / 255, blue: 0x4E / 255),
            dark: SwiftUI.Color(red: 0x7F / 255, green: 0xA1 / 255, blue: 0x89 / 255)
        )
        static let divider = SwiftUI.Color(
            light: SwiftUI.Color(red: 35 / 255, green: 40 / 255, blue: 35 / 255).opacity(0.08),
            dark: SwiftUI.Color.white.opacity(0.08)
        )
        static let cardBackground = SwiftUI.Color(
            light: SwiftUI.Color.white,
            dark: SwiftUI.Color(red: 0x27 / 255, green: 0x2A / 255, blue: 0x26 / 255)
        )
    }

    enum Font {
        enum BodyWeight {
            case regular, medium, bold
        }

        static func headline(_ size: CGFloat) -> SwiftUI.Font {
            .custom("Lora-Medium", size: size)
        }

        static func headlineRegular(_ size: CGFloat) -> SwiftUI.Font {
            .custom("Lora-Regular", size: size)
        }

        static func body(_ size: CGFloat, weight: BodyWeight = .regular) -> SwiftUI.Font {
            switch weight {
            case .regular: return .custom("DMSans-Regular", size: size)
            case .medium: return .custom("DMSans-Medium", size: size)
            case .bold: return .custom("DMSans-Bold", size: size)
            }
        }
    }
}
