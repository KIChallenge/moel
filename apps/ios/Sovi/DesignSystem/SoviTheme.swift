import SwiftUI
import UIKit

enum SoviTheme {
    static let background = adaptive(0xFFFFFF, 0x17191B)
    static let ink = adaptive(0x3C3C3C, 0xEDEEEF)
    static let secondary = adaptive(0x737373, 0xB8BABC)
    static let accent = adaptive(0x006F48, 0xA9D8BC)
    static let softGreen = adaptive(0xE8F5EF, 0x21372E)
    static let bubble = adaptive(0xFFFFFF, 0x27292B)
    static let border = adaptive(0xE5E5E5, 0x454749)
    static let orange = Color(hex: 0xE9A35C)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Native glass for controls, with a material fallback and an opaque accessibility mode.
private struct SoviGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(SoviTheme.background, in: shape)
                .overlay(shape.strokeBorder(SoviTheme.border, lineWidth: 1).allowsHitTesting(false))
        } else if #available(iOS 26.0, *) {
            // Keep editable text and button labels outside the glass rendering layer.
            // The effect is decorative; native controls own their hit testing.
            content.background {
                shape.fill(.clear)
                    .glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
                    .allowsHitTesting(false)
            }
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(SoviTheme.border.opacity(0.7), lineWidth: 1).allowsHitTesting(false))
        }
    }
}

extension View {
    func soviGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(SoviGlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

