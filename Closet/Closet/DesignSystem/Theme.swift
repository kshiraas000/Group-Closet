import SwiftUI

enum Theme {
    enum Color {
        static let background = SwiftUI.Color(red: 0xF7 / 255, green: 0xF6 / 255, blue: 0xF1 / 255)
        static let primaryText = SwiftUI.Color(red: 0x23 / 255, green: 0x28 / 255, blue: 0x23 / 255)
        static let secondaryText = SwiftUI.Color(red: 0x6D / 255, green: 0x73 / 255, blue: 0x70 / 255)
        static let tertiaryText = SwiftUI.Color(red: 0x8B / 255, green: 0x91 / 255, blue: 0x8C / 255)
        static let accent = SwiftUI.Color(red: 0x4A / 255, green: 0x5D / 255, blue: 0x4E / 255)
        static let divider = SwiftUI.Color(red: 35 / 255, green: 40 / 255, blue: 35 / 255).opacity(0.08)
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
