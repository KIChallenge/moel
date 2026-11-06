import SwiftUI

struct PathCompanionSlotBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Reserves the natural size of Sovi's stop, even when the button is at an edge.
struct PathCompanionSlot: View {
    let prompt: PathCompanionPrompt
    let width: CGFloat
    static let mascotSize: CGFloat = 140
    static let spacing: CGFloat = 12

    var body: some View {
        VStack(spacing: Self.spacing) {
            PathCompanionBubble(text: prompt.text, width: width)
            Color.clear.frame(width: Self.mascotSize, height: Self.mascotSize)
        }
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .anchorPreference(key: PathCompanionSlotBounds.self, value: .bounds) { $0 }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A single button travels with the scroll content until it settles at a corner.
struct PathCompanionView: View {
    let prompt: PathCompanionPrompt
    let slot: CGRect
    let viewport: CGRect
    let contentWidth: CGFloat
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let routeSize = PathCompanionSlot.mascotSize
        let dockSize: CGFloat = 64
        let inset: CGFloat = 8
        let top = min(viewport.midY, viewport.minY + inset + dockSize / 2)
        let bottom = max(viewport.midY, viewport.maxY - inset - dockSize / 2)
        let routeY = slot.maxY - routeSize / 2
        let distance = min(routeY - top, bottom - routeY)
        let approach = min(84, max(1, (bottom - top) / 2))
        let fraction = max(0, min(1, 1 - distance / approach))
        let blend = reduceMotion ? (distance <= 0 ? 1.0 : 0.0) : fraction * fraction * (3 - 2 * fraction)
        let clampedY = min(bottom, max(top, routeY))
        let edgeY = routeY < viewport.midY ? top : bottom
        let centerY = clampedY + (edgeY - clampedY) * blend

        let size = routeSize + (dockSize - routeSize) * blend
        let trailingX = layoutDirection == .leftToRight ? contentWidth - inset - dockSize / 2 : inset + dockSize / 2
        let centerX = slot.midX + (trailingX - slot.midX) * blend
        let width = slot.width + (dockSize - slot.width) * blend
        let fullBubbleHeight = max(0, slot.height - routeSize - PathCompanionSlot.spacing)
        let bubbleHeight = fullBubbleHeight * (1 - blend)
        let gap = PathCompanionSlot.spacing * (1 - blend)
        let height = bubbleHeight + gap + size

        Button(action: action) {
            VStack(spacing: 0) {
                PathCompanionBubble(text: prompt.text, width: slot.width)
                    .padding(.bottom, PathCompanionSlot.spacing)
                    .frame(width: width, height: bubbleHeight + gap, alignment: .bottom)
                    .clipped()
                    .opacity(1 - blend)
                SoviMascot(size: size)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Sovi: \(prompt.text)"))
        .accessibilityValue(Text(LocalizedStringKey(routeY <= top ? "Am oberen Rand" : routeY >= bottom ? "Am unteren Rand" : "Auf deinem Weg")))
        .accessibilityHint("Öffnet das Gespräch mit Sovi.")
        .accessibilityIdentifier("path.sovi")
        .position(x: centerX, y: centerY + size / 2 - height / 2)
    }
}

private struct PathCompanionBubble: View {
    let text: String
    let width: CGFloat
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded, weight: .bold))
            .foregroundStyle(SoviTheme.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(textSize.isAccessibilitySize ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(width: width, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 14).fill(SoviTheme.bubble) }
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(SoviTheme.border, lineWidth: 2) }
            .overlay(alignment: .bottom) {
                SpeechBubbleTail()
                    .fill(SoviTheme.bubble)
                    .overlay {
                        SpeechBubbleTailOutline()
                            .stroke(SoviTheme.border, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    .frame(width: 18, height: 12)
                    .offset(y: 10)
            }
            .accessibilityHidden(true)
    }
}

private struct SpeechBubbleTailOutline: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        }
    }
}

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.closeSubpath()
        }
    }
}
