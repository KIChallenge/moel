import SwiftUI

struct SoviChatBubble: View {
    let text: String
    let isUser: Bool
    var language: String? = nil
    var read: (() -> Void)? = nil
    var identifier = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 38) }
            else { SoviMascot(size: 42, expression: .calm).accessibilityHidden(true).padding(.top, 4) }
            VStack(alignment: .leading, spacing: 4) {
                Text(isUser ? String(localized: "Du") : "Sovi")
                    .font(.caption.weight(.semibold)).foregroundStyle(SoviTheme.secondary)
                HStack(alignment: .top, spacing: 8) {
                    if let read, !isUser {
                        Button(action: read) { Image(systemName: "speaker.wave.2.fill").frame(width: 44, height: 44) }
                            .accessibilityLabel("Nachricht vorlesen")
                    }
                    Text(text).font(.system(.body, design: .rounded))
                        .accessibilityIdentifier(identifier)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(isUser ? SoviTheme.softGreen : SoviTheme.background, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(SoviTheme.secondary.opacity(0.22), lineWidth: 1.5))
                .overlay(alignment: isUser ? .topTrailing : .topLeading) {
                    Image(systemName: isUser ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                        .font(.system(size: 12)).foregroundStyle(isUser ? SoviTheme.softGreen : SoviTheme.background)
                        .offset(x: isUser ? 7 : -7, y: 16).accessibilityHidden(true)
                }
            }
            if !isUser { Spacer(minLength: 10) }
        }
        .accessibilityElement(children: .contain)
    }
}
