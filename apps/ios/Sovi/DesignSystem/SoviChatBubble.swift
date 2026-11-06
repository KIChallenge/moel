import SwiftUI

struct ChatActionLabel: View {
    let title: Text
    var systemImage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            title
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }
}

struct ChatActionButtonStyle: ButtonStyle {
    var tone: SoviButtonTone = .green
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        let pressed = enabled && configuration.isPressed
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .foregroundStyle(enabled ? SoviTheme.ink : SoviTheme.secondary)
            .background(enabled ? tone.surface : SoviTheme.bubble, in: shape)
            .overlay {
                shape.strokeBorder(SoviTheme.ink.opacity(contrast == .increased ? 0.6 : 0.18), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
            .offset(y: pressed ? 3 : 0)
            .padding(.bottom, 4)
            .background {
                shape.fill(SoviTheme.ink.opacity(enabled ? 0.28 : 0.12))
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
    }
}

/// Delivery is presentation state. The actual conversation stays in its store.
struct ChatTurnKey: Equatable {
    let id: String
    let isUser: Bool

    init(_ id: String, isUser: Bool) {
        self.id = id
        self.isUser = isUser
    }

    init(_ turn: ConversationTurn) {
        self.init(turn.id.uuidString, isUser: turn.role == "user")
    }
}

struct ChatTimeline: Equatable {
    var turns: [ChatTurnKey]
    var awaitingNetwork = false
    var immediate = false
}

@Observable @MainActor
final class ChatDelivery {
    static let typingID = "chat.typing"
    static let revealDuration = 0.34
    private(set) var visible: Set<String> = []
    private(set) var expanding: String?
    private var restored = false
    @ObservationIgnored private var typing: (after: String, since: ContinuousClock.Instant)?

    func restore(_ existing: [ChatTurnKey]) {
        guard !restored else { return }
        visible = Set(existing.map(\.id))
        restored = true
    }

    func isTyping(_ timeline: ChatTimeline) -> Bool {
        restored && (timeline.awaitingNetwork || (!timeline.immediate && timeline.turns.contains { !$0.isUser && !visible.contains($0.id) }))
    }

    func writingID(_ timeline: ChatTimeline) -> String? {
        guard restored, !timeline.immediate, expanding == nil,
              let next = timeline.turns.first(where: { !visible.contains($0.id) }), !next.isUser else { return nil }
        return next.id
    }

    func displays(_ id: String, writingID: String?) -> Bool {
        visible.contains(id) || expanding == id || writingID == id
    }

    private func typingStart(after id: String) -> ContinuousClock.Instant {
        if let typing, typing.after == id { return typing.since }
        let start = ContinuousClock.now
        typing = (id, start)
        return start
    }

    /// Called in a view-scoped .task(id:) so dismissal, reset and a new turn cancel the pending reveal.
    func present(_ timeline: ChatTimeline, reduceMotion: Bool, onAssistant: (String) -> Void = { _ in }) async {
        let clock = ContinuousClock()
        for (index, turn) in timeline.turns.enumerated() where !visible.contains(turn.id) {
            guard !Task.isCancelled else { return }
            let paced = !turn.isUser && !timeline.immediate
            if paced {
                let predecessor = index > 0 ? timeline.turns[index - 1].id : turn.id
                let start = typingStart(after: predecessor)
                do { try await clock.sleep(until: start.advanced(by: .milliseconds(780))) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            let morph = paced && !reduceMotion
            withAnimation(reduceMotion || timeline.immediate ? nil : .easeInOut(duration: morph ? Self.revealDuration : 0.2)) {
                if morph { expanding = turn.id }
                _ = visible.insert(turn.id)
            }
            if !turn.isUser {
                typing = nil
                if morph {
                    do { try await clock.sleep(for: .seconds(Self.revealDuration)) }
                    catch { if expanding == turn.id { expanding = nil }; return }
                    expanding = nil
                }
                onAssistant(turn.id)
            }
        }
        if timeline.awaitingNetwork, let last = timeline.turns.last { _ = typingStart(after: last.id) }
        else { typing = nil }
    }
}

extension AnyTransition {
    static var chatMessage: Self { .asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity) }
}

private struct SoviTypingDots: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 7
    @State private var start = Date()

    var body: some View {
        if active && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { tick in
                dots(elapsed: tick.date.timeIntervalSince(start))
            }
        } else { dots(elapsed: nil) }
    }

    private func dots(elapsed: TimeInterval?) -> some View {
        HStack(spacing: dot * 0.6) {
            ForEach(0..<3) { index in
                let phase = ((elapsed ?? 0) / 0.95 - Double(index) / 3) * (2 * Double.pi)
                Circle().fill(SoviTheme.accent)
                    .opacity(elapsed == nil ? 0.8 : 0.38 + 0.62 * max(0, cos(phase)))
                    .frame(width: dot, height: dot)
            }
        }
    }
}

/// Both faces stay in one row. Measure the text at its final width while the
/// rounded surface grows, so the words don't rewrap during the reveal.
private struct AssistantBubbleLayout: Layout {
    var expansion: CGFloat
    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let compact = subviews[0].sizeThatFits(.unspecified)
        let full = subviews[1].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: compact.width + (full.width - compact.width) * expansion,
                      height: compact.height + (full.height - compact.height) * expansion)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
        subviews[1].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: proposal.width, height: nil))
    }
}

struct SoviChatBubble: View {
    let text: String
    let isUser: Bool
    var isWriting = false
    var language: String? = nil
    var read: (() -> Void)? = nil
    var identifier = ""
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expansion: CGFloat?
    private var fraction: CGFloat { expansion ?? (isWriting ? 0 : 1) }

    private var rightToLeft: Bool {
        language == "ar" || text.range(of: "[\\u0600-\\u06FF]", options: .regularExpression) != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            if isUser {
                if !textSize.isAccessibilitySize { Spacer(minLength: 28) }
                message.background(SoviTheme.bubble, in: RoundedRectangle(cornerRadius: 20))
            } else {
                AssistantBubbleLayout(expansion: fraction) {
                    HStack(spacing: 8) {
                        author
                        SoviTypingDots(active: isWriting).padding(.leading, 3)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44).padding(.vertical, 6)
                    .opacity(1 - fraction)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text((language.flatMap(ChatLanguage.init(rawValue:)) ?? .app).text("Sovi schreibt …")))
                    .accessibilityIdentifier(isWriting ? ChatDelivery.typingID : "")
                    .accessibilityHidden(!isWriting)

                    message.opacity(fraction).accessibilityHidden(isWriting)
                        .allowsHitTesting(!isWriting)
                }
                .background(SoviTheme.softGreen)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
        .accessibilityElement(children: .contain)
        .onChange(of: isWriting, initial: true) { _, writing in
            let target: CGFloat = writing ? 0 : 1
            if expansion == nil { expansion = target }
            else { withAnimation(reduceMotion ? nil : .easeInOut(duration: ChatDelivery.revealDuration)) { expansion = target } }
        }
    }

    @ViewBuilder private var author: some View {
        if !isUser { SoviMascot(size: 26).accessibilityHidden(true) }
        Text(isUser ? String(localized: "Du") : "Sovi")
            .font(.caption.weight(.semibold)).foregroundStyle(SoviTheme.secondary)
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                author
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
    }
}
