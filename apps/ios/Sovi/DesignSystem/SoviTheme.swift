import SwiftUI
import UIKit

enum SoviTheme {
    // Shared with the Sovi website: a quiet green canvas and simple white cards.
    static let background = adaptive(0xF0F8E7, 0x182117)
    static let ink = adaptive(0x294226, 0xEFF7E7)
    static let secondary = adaptive(0x5D7055, 0xBBCDB0)
    static let accent = adaptive(0x3F7D00, 0xC8EC9F)
    static let softGreen = adaptive(0xD7F2B4, 0x304528)
    static let action = adaptive(0xC8EC9F, 0x395329)
    static let bubble = adaptive(0xFFFFFF, 0x253021)
    static let border = adaptive(0xCADCB9, 0x4B5F40)
    static let missed = adaptive(0xCC3D41, 0xFF9287)
    static let sky = adaptive(0xC8E8FF, 0x254660)
    static let lilac = adaptive(0xE7DAFF, 0x46395B)
    static let coral = adaptive(0xFFDAD5, 0x573332)
    static let orange = Color(hex: 0xE2B749)

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

