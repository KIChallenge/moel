import SwiftUI

struct SoviChatBubble: View {
    let text: String
    let isUser: Bool
    var language: String? = nil
    var read: (() -> Void)? = nil
    var identifier = ""
    @Environment(\.dynamicTypeSize) private var textSize

    private var rightToLeft: Bool {
        language == "ar" || text.range(of: "[\\u0600-\\u06FF]", options: .regularExpression) != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            if isUser && !textSize.isAccessibilitySize { Spacer(minLength: 28) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if !isUser { SoviMascot(size: 26).accessibilityHidden(true) }
                    Text(isUser ? String(localized: "Du") : "Sovi")
                        .font(.caption.weight(.semibold)).foregroundStyle(SoviTheme.secondary)
                    Spacer(minLength: 0)
                    if let read, !isUser {
                        Button(action: read) {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 20)).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Nachricht vorlesen")
                    }
                }
                Text(text).font(.system(.body, design: .rounded))
                    .accessibilityIdentifier(identifier)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 14)
            .background(isUser ? SoviTheme.softGreen : SoviTheme.bubble, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(SoviTheme.border, lineWidth: isUser ? 1 : 1.5).allowsHitTesting(false))
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        }
        .accessibilityElement(children: .contain)
    }
}
