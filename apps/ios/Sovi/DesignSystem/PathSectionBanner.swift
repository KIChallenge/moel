import SwiftUI
import UIKit

/// Counts of stored records; no score or inferred medical status.
struct PathOverviewStrip: View {
    let appointments: Int
    let documents: Int
    let vaccinations: Int
    let tasks: Int
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                appointmentCount; Spacer(minLength: 8)
                documentCount; Spacer(minLength: 8)
                vaccinationCount; Spacer(minLength: 8)
                taskCount
            }
            VStack(spacing: 8) {
                HStack { appointmentCount; Spacer(); documentCount }
                HStack { vaccinationCount; Spacer(); taskCount }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
    }

    private var appointmentCount: some View { count(appointments, symbol: "calendar", color: Color(hex: 0x008E5C), label: "Termine") }
    private var documentCount: some View { count(documents, symbol: "doc.text.fill", color: Color(hex: 0xA263D4), label: "Dokumente") }
    private var vaccinationCount: some View { count(vaccinations, symbol: "syringe.fill", color: Color(hex: 0x129BDC), label: "Impfungen") }
    private var taskCount: some View { count(tasks, symbol: "checklist", color: Color(hex: 0xB77D00), label: "Offene Aufgaben") }

    private func count(_ value: Int, symbol: String, color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(textSize.isAccessibilitySize ? .system(size: 20, weight: .heavy) : .system(.title3, design: .rounded, weight: .heavy))
            Text(value, format: .number).font(.system(textSize.isAccessibilitySize ? .caption2 : .title3, design: .rounded, weight: .heavy))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value, format: .number))
    }
}

struct PathActionBubble: View {
    let title: String
    let tint: Color
    @Environment(\.locale) private var locale
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(title.uppercased(with: locale))
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .foregroundStyle(contrast == .increased ? SoviTheme.ink : tint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13).padding(.top, 7).padding(.bottom, 15)
            .background { ActionBubbleOutline().fill(SoviTheme.bubble) }
            .overlay { ActionBubbleOutline().stroke(contrast == .increased ? SoviTheme.secondary : SoviTheme.border, lineWidth: 2) }
            .frame(minWidth: 44, minHeight: 44, alignment: .bottom)
            .contentShape(Rectangle())
    }
}

private struct ActionBubbleOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: 1, dy: 1)
        let bottom = bounds.maxY - 7
        let left = bounds.minX, right = bounds.maxX, top = bounds.minY, middle = bounds.midX
        return Path { path in
            path.move(to: CGPoint(x: left + 9, y: top))
            path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: bottom), radius: 9)
            path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: middle + 8, y: bottom), radius: 9)
            path.addLine(to: CGPoint(x: middle + 8, y: bottom))
            path.addLine(to: CGPoint(x: middle + 1.5, y: bounds.maxY - 1))
            path.addQuadCurve(to: CGPoint(x: middle - 1.5, y: bounds.maxY - 1), control: CGPoint(x: middle, y: bounds.maxY + 0.5))
            path.addLine(to: CGPoint(x: middle - 8, y: bottom))
            path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: top), radius: 9)
            path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: right, y: top), radius: 9)
            path.closeSubpath()
        }
    }
}

/// Intercepts the system status-bar shortcut while preserving SwiftUI's scroll delegate.
struct PathStatusBarScroll: UIViewRepresentable {
    var enabled = true
    var goToLatest: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(goToLatest) }
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.coordinator = context.coordinator
        return view
    }
    func updateUIView(_ view: Probe, context: Context) {
        context.coordinator.goToLatest = goToLatest
        context.coordinator.enabled = enabled
        view.install()
    }
    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) { coordinator.detach() }

    final class Probe: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() { super.didMoveToWindow(); install() }
        func install() {
            guard window != nil else { return }
            // The hosting hierarchy is completed after the representable update.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let scroll = view as? UIScrollView { self.coordinator?.attach(scroll); return }
                    ancestor = view.superview
                }
            }
        }
    }
    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        var goToLatest: () -> Void
        var enabled = true
        private weak var scroll: UIScrollView?
        private weak var original: (any UIScrollViewDelegate)?
        private var originalScrollsToTop = true
        init(_ action: @escaping () -> Void) { goToLatest = action }
        func attach(_ view: UIScrollView) {
            guard view.delegate !== self else { view.scrollsToTop = enabled; return }
            detach()
            scroll = view; original = view.delegate
            originalScrollsToTop = view.scrollsToTop
            view.scrollsToTop = enabled
            view.delegate = self
        }
        func detach() {
            if scroll?.delegate === self { scroll?.delegate = original; scroll?.scrollsToTop = originalScrollsToTop }
            scroll = nil; original = nil
        }
        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            goToLatest()
            return false
        }
        // UIKit inspects and invokes its scroll delegate on the main thread.
        override nonisolated func responds(to selector: Selector!) -> Bool {
            if super.responds(to: selector) { return true }
            return MainActor.assumeIsolated { original?.responds(to: selector) == true }
        }
        override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
            let fallback = super.forwardingTarget(for: selector)
            // This synchronous Objective-C callback never transfers the target off the UI thread.
            let target = MainActor.assumeIsolated { ForwardTarget(value: original?.responds(to: selector) == true ? original : nil) }
            return target.value ?? fallback
        }
        private struct ForwardTarget: @unchecked Sendable { let value: Any? }
    }
}
