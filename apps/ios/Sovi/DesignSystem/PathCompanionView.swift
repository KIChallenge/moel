import SwiftUI

enum PathCompanionPlacement { case route, top, bottom }

/// The same companion and Focus entrance, whether on the path or peeking at an edge.
struct PathCompanionView: View {
    let prompt: PathCompanionPrompt
    var placement: PathCompanionPlacement = .route
    var bubbleWidth: CGFloat = 168
    var routeMascotSize: CGFloat = 140
    var isActive = true
    var namespace: Namespace.ID
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Button(action: action) {
            Group {
                if placement == .route {
                    VStack(spacing: 12) {
                        bubble
                        mascot(size: routeMascotSize)
                    }
                    .frame(width: bubbleWidth)
                } else if textSize.isAccessibilitySize {
                    HStack(spacing: 12) {
                        mascot(size: 48)
                        Text("Mit Sovi sprechen")
                            .font(.headline).foregroundStyle(SoviTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "bubble.left.fill").foregroundStyle(SoviTheme.accent)
                    }
                    .padding(16).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    HStack(alignment: placement == .top ? .top : .bottom, spacing: 6) {
                        bubble.padding(.vertical, 12)
                        peekingMascot
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, 20).padding(.trailing, 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Sovi: \(prompt.text)"))
        .accessibilityValue(Text(LocalizedStringKey(placement == .route ? "Auf deinem Weg" : placement == .top ? "Am oberen Rand" : "Am unteren Rand")))
        .accessibilityHint("Öffnet das Gespräch mit Sovi.")
        .accessibilityIdentifier("path.sovi")
    }

    private var peekingMascot: some View {
        mascot(size: 108)
            .rotationEffect(.degrees(placement == .top ? -8 : 8))
            .offset(y: placement == .top ? -22 : 0)
            .frame(width: 108, height: 76, alignment: .top)
            .clipped()
    }

    @ViewBuilder private func mascot(size: CGFloat) -> some View {
        if isActive {
            SoviMascot(size: size)
                .matchedGeometryEffect(id: "sovi", in: namespace, properties: reduceMotion ? [] : .frame)
        } else {
            SoviMascot(size: size)
        }
    }

    private var bubble: some View {
        Text(prompt.text)
            .font(.system(.callout, design: .rounded, weight: .bold))
            .foregroundStyle(SoviTheme.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(textSize.isAccessibilitySize ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: bubbleWidth, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(SoviTheme.bubble)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(SoviTheme.border, lineWidth: 2)
            }
            .overlay(alignment: placement == .route ? .bottom : .trailing) {
                SpeechBubbleTail()
                    .fill(SoviTheme.bubble)
                    .overlay {
                        SpeechBubbleTailOutline()
                            .stroke(SoviTheme.border, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    .frame(width: 18, height: 12)
                    .rotationEffect(.degrees(placement == .route ? 0 : -90))
                    .offset(x: placement == .route ? 0 : 10, y: placement == .route ? 10 : 0)
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
