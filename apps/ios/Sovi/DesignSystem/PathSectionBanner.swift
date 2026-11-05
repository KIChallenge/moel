import SwiftUI

struct PathSectionBanner: View {
    var caption: String = ""
    let title: String
    var openControls: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                if !caption.isEmpty {
                    Text(caption.uppercased())
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                }
                Text(LocalizedStringKey(title))
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let openControls {
                Button(action: openControls) {
                    Image(systemName: "ellipsis")
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Einstellungen")
                .accessibilityIdentifier("path.controls")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(SoviTheme.bannerGreen, in: RoundedRectangle(cornerRadius: 13))
        .background(Color(hex: 0x00623E), in: RoundedRectangle(cornerRadius: 13).offset(y: 5))
        .padding(.bottom, 5)
    }
}

/// Counts of stored records; no score or inferred medical status.
struct PathOverviewStrip: View {
    let appointments: Int
    let documents: Int
    let vaccinations: Int
    let tasks: Int
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    HStack { appointmentCount; Spacer(); documentCount }
                    HStack { vaccinationCount; Spacer(); taskCount }
                }
            } else {
                HStack {
                    appointmentCount; Spacer(minLength: 8)
                    documentCount; Spacer(minLength: 8)
                    vaccinationCount; Spacer(minLength: 8)
                    taskCount
                }
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
            Image(systemName: symbol).font(.system(.title3, design: .rounded, weight: .heavy))
            Text(value, format: .number).font(.system(.title3, design: .rounded, weight: .heavy))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value, format: .number))
    }
}

struct PathTodayMarker: View {
    var title: String = String(localized: "Heute")

    var body: some View {
        Text(title.uppercased())
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .foregroundStyle(SoviTheme.accent)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(SoviTheme.bubble, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(SoviTheme.border, lineWidth: 2) }
            .overlay(alignment: .bottom) {
                MarkerTail().fill(SoviTheme.bubble)
                    .overlay { MarkerTail().stroke(SoviTheme.border, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)) }
                    .overlay(alignment: .top) { Rectangle().fill(SoviTheme.bubble).frame(width: 14, height: 3).offset(y: -1) }
                    .frame(width: 18, height: 10).offset(y: 8)
            }
            .accessibilityHidden(true)
    }
}

private struct MarkerTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        }
    }
}
