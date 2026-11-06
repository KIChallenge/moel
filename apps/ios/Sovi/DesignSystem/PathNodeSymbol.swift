import SwiftUI

/// Visual topics only: these symbols never change a record's kind or status.
enum PathTopic: CaseIterable {
    case beginning, childhood, independence, present, discharge, documents
    case aftercare, therapy, followUp, medication, clarification, administration
    case appointment, phone, task, information, event
    case day, screening, pediatrician, vaccination, dental, vision, school
    case insurance, card, work, infection, feedback, fracture, laboratory, measurement, questionnaire, invoice

    var symbolName: String {
        switch self {
        case .beginning: "sunrise.fill"
        case .childhood: "teddybear.fill"
        case .independence: "key.fill"
        case .present: "sun.max.fill"
        case .discharge: "cross.case.fill"
        case .documents: "doc.text.magnifyingglass"
        case .aftercare: "book.closed.fill"
        case .therapy: "figure.walk"
        case .followUp: "stethoscope"
        case .medication: "pills.fill"
        case .clarification: "questionmark.bubble.fill"
        case .administration: "square.and.pencil"
        case .appointment: "calendar"
        case .phone: "phone.fill"
        case .task: "checklist"
        case .information: "info.circle.fill"
        case .event: "sparkles"
        case .day: "square.stack.3d.up.fill"
        case .screening: "drop.fill"
        case .pediatrician: "stethoscope"
        case .vaccination: "syringe.fill"
        case .dental: "mouth.fill"
        case .vision: "eye.fill"
        case .school: "graduationcap.fill"
        case .insurance: "person.crop.rectangle.fill"
        case .card: "creditcard.fill"
        case .work: "briefcase.fill"
        case .infection: "thermometer.medium"
        case .feedback: "bubble.left.fill"
        case .fracture: "bandage.fill"
        case .laboratory: "testtube.2"
        case .measurement: "ruler.fill"
        case .questionnaire: "list.bullet.rectangle"
        case .invoice: "doc.plaintext"
        }
    }

    fileprivate var tone: PathSymbolTone {
        switch self {
        case .beginning, .present, .documents, .clarification, .day, .measurement, .invoice: .gold
        case .childhood, .medication, .vaccination, .dental, .fracture, .infection: .coral
        case .independence, .aftercare, .administration, .appointment, .vision, .school, .insurance, .card, .work, .questionnaire, .laboratory: .blue
        case .therapy: .lavender
        case .discharge, .followUp, .phone, .task, .information, .event, .screening, .pediatrician, .feedback: .green
        }
    }
}

fileprivate enum PathSymbolTone {
    case green, gold, coral, blue, lavender

    var light: (surface: UInt32, ink: UInt32, base: UInt32) {
        switch self {
        case .green: (0xDDEFE5, 0x246A4E, 0xA5CCB6)
        case .gold: (0xFAEDCE, 0x876529, 0xDBCA9C)
        case .coral: (0xF8E5DF, 0xA05C4B, 0xDEB8AA)
        case .blue: (0xE2EDF5, 0x436D89, 0xB3CBDC)
        case .lavender: (0xEDE7F6, 0x715B94, 0xC9BADD)
        }
    }

    var dark: (surface: UInt32, ink: UInt32, base: UInt32) {
        switch self {
        case .green: (0x284E3D, 0xB0E1C6, 0x1A382A)
        case .gold: (0x51452D, 0xF1D797, 0x352D1D)
        case .coral: (0x563C36, 0xF1C2B2, 0x3A2723)
        case .blue: (0x2D4657, 0xBDDDED, 0x1C2F3C)
        case .lavender: (0x453A56, 0xD8C9EF, 0x2E263B)
        }
    }
}

struct PathSymbolPalette {
    let surface: Color
    let ink: Color
    let base: Color

    init(topic: PathTopic, progress: PathProgress = .neutral, scheme: ColorScheme) {
        let values: (surface: UInt32, ink: UInt32, base: UInt32)
        switch progress {
        case .pending, .inactive:
            values = scheme == .dark ? (0x343B38, 0xBEC5C1, 0x202722) : (0xE6E6E6, 0x686E6B, 0xB9B9B9)
        case .missed:
            values = scheme == .dark ? (0x542C31, 0xFFD0D5, 0x351B20) : (0xFBE3E5, 0xA42A3A, 0xDFA0A8)
        case .neutral, .done:
            values = scheme == .dark ? topic.tone.dark : topic.tone.light
        }
        surface = Color(hex: values.surface)
        ink = Color(hex: values.ink)
        base = Color(hex: values.base)
    }
}

struct PathNodeSymbol: View {
    let topic: PathTopic
    var size: CGFloat = 32
    var tintColor: Color?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if case .dental = topic {
                ToothSymbol().fill(tintColor ?? PathSymbolPalette(topic: topic, scheme: colorScheme).ink)
                    .frame(width: size * 0.9, height: size)
            } else {
                Image(systemName: topic.symbolName)
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .symbolRenderingMode(tintColor == nil ? .hierarchical : .monochrome)
                    .foregroundStyle(tintColor ?? PathSymbolPalette(topic: topic, scheme: colorScheme).ink)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Topic and record state remain independent from the current-day emphasis.
struct PathNodeButton: View {
    let node: PathNode
    let statusText: String
    let actionTitle: String
    var entryCount = 1
    var dateIncludesTime = true
    var currentMarker: String?
    var compact = true
    var progress: PathProgress = .neutral
    var buttonIdentifier: String?
    var labelTitle: String?
    var selectionAnchor = false
    var activeEntryIndex: Int?
    var action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.timeZone) private var timeZone
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .caption2) private var dateSize = 10.0
    @ScaledMetric(relativeTo: .body) private var expandedWidth = 76.0
    @ScaledMetric(relativeTo: .body) private var expandedHeight = 66.0
    @ScaledMetric(relativeTo: .body) private var expandedIcon = 32.0

    private var usesCompactLayout: Bool { compact && !textSize.isAccessibilitySize }
    private var isCurrent: Bool { currentMarker != nil }
    private var faceWidth: CGFloat { textSize.isAccessibilitySize ? 76 : usesCompactLayout ? 70 : expandedWidth }
    private var faceHeight: CGFloat { textSize.isAccessibilitySize ? 66 : usesCompactLayout ? 60 : expandedHeight }
    private var palette: PathSymbolPalette { .init(topic: node.routeTopic, progress: progress, scheme: colorScheme) }
    private var icon: Color {
        contrast == .increased && (progress == .neutral || progress == .done) ? SoviTheme.ink : palette.ink
    }
    private var halo: Color {
        progress == .missed ? icon : isCurrent ? SoviTheme.accent : icon
    }

    var body: some View {
        if textSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    controlColumn.fixedSize(horizontal: true, vertical: false)
                    caption.frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: 8) { controlColumn; caption }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        } else {
            VStack(spacing: usesCompactLayout ? 4 : 8) {
                controlColumn
                caption
            }
            .frame(width: usesCompactLayout ? 160 : 200)
            .padding(.vertical, 6)
        }
    }

    private var controlColumn: some View {
        VStack(spacing: 2) {
            Button(action: action) {
                PathActionBubble(title: actionTitle, tint: isCurrent ? SoviTheme.accent : icon)
            }
            .buttonStyle(.plain)
            .opacity(selectionAnchor ? 0 : 1)
            .allowsHitTesting(!selectionAnchor)
            .accessibilityHidden(true)
            diskButton
        }
    }

    private var caption: some View {
        VStack(alignment: textSize.isAccessibilitySize ? .leading : .center, spacing: usesCompactLayout ? 4 : 8) { labels }
            .opacity(selectionAnchor ? 0 : 1)
    }

    private var diskButton: some View {
        Button(action: action) {
            PathNodeSymbol(topic: node.routeTopic, size: textSize.isAccessibilitySize ? 32 : usesCompactLayout ? 30 : expandedIcon,
                           tintColor: icon)
                .frame(width: faceWidth, height: faceHeight)
                .background(palette.surface, in: Ellipse())
                .overlay(alignment: .bottomTrailing) {
                    if progress == .done || progress == .missed || node.kind == .information && node.informationRead {
                        Image(systemName: progress == .missed ? "xmark.circle.fill" : progress == .done ? "checkmark.circle.fill" : "eye.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(progress == .missed ? icon : SoviTheme.accent, SoviTheme.background)
                            .background(SoviTheme.background, in: Circle())
                            .offset(x: 3, y: 4)
                    }
                }
        }
        .buttonStyle(PathNodePressStyle(base: palette.base, diameter: max(faceWidth, faceHeight + 8) + 24,
                                        count: entryCount, haloColor: halo, emphasized: isCurrent || selectionAnchor,
                                        activeEntryIndex: activeEntryIndex))
        .anchorPreference(key: PathSelectedButtonBounds.self, value: .bounds) { selectionAnchor ? $0 : nil }
        .accessibilityLabel(Text(labelTitle ?? node.displayTitle))
        .accessibilityValue(Text(accessibilitySummary))
        .accessibilityHint(Text(actionTitle))
        .accessibilityIdentifier(buttonIdentifier ?? "path.node.\(node.kind.rawValue).\(node.id)")
    }

    @ViewBuilder private var labels: some View {
        Text(labelTitle ?? node.displayTitle)
            .font(.system(usesCompactLayout ? .caption : .subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(SoviTheme.ink)
            .multilineTextAlignment(textSize.isAccessibilitySize ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
        if node.date != nil || isCurrent {
            let date = node.date.map { formattedDate($0, abbreviated: usesCompactLayout) }
            Text([currentMarker, date].compactMap { $0 }.joined(separator: " · "))
                .font(usesCompactLayout ? .system(size: dateSize, weight: .bold, design: .rounded) : .caption.weight(.medium))
                .foregroundStyle(isCurrent ? SoviTheme.accent : SoviTheme.secondary)
                .accessibilityHidden(true)
        }
        if !statusText.isEmpty && (!usesCompactLayout || entryCount > 1) {
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(SoviTheme.secondary)
                .multilineTextAlignment(textSize.isAccessibilitySize ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        if progress == .missed {
            Text("Verpasst").font(.caption2.weight(.semibold)).foregroundStyle(icon).accessibilityHidden(true)
        }
    }

    private func formattedDate(_ date: Date, abbreviated: Bool = false) -> String {
        var style: Date.FormatStyle
        if dateIncludesTime { style = Date.FormatStyle().day().month(.abbreviated).hour().minute() }
        else if abbreviated { style = Date.FormatStyle().day().month(.twoDigits) }
        else { style = Date.FormatStyle().day().month(.wide).year() }
        style.timeZone = timeZone
        style.calendar = calendar
        style.locale = locale
        return date.formatted(style)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if !progress.title.isEmpty { parts.append(progress.title) }
        if let currentMarker { parts.append(currentMarker) }
        if let date = node.date { parts.append(formattedDate(date)) }
        if entryCount > 1 && !statusText.contains(String(entryCount)) {
            parts.append(String(localized: "\(entryCount) Einträge"))
        }
        if !statusText.isEmpty { parts.append(statusText) }
        return parts.joined(separator: ", ")
    }
}

/// The accented segment locates an entry in its day; it never implies that a visit was attended.
private struct DayEntryHalo: View {
    let count: Int
    let color: Color
    let diameter: CGFloat
    let activeEntryIndex: Int?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let thickness = min(7, diameter * .pi / CGFloat(count) * 0.38)
        let ring = Circle().inset(by: thickness / 2)
        let neutral = contrast == .increased ? SoviTheme.secondary : SoviTheme.border
        let halfGap = min(0.23 / CGFloat(count), (thickness + 3) / (2 * .pi * (diameter - thickness)))
        ZStack {
            ring.stroke(neutral.opacity(0.25), lineWidth: thickness)
            if count == 1 {
                ring.stroke(color, lineWidth: thickness)
            } else {
                ForEach(0..<count, id: \.self) { index in
                    ring.trim(from: CGFloat(index) / CGFloat(count) + halfGap,
                              to: CGFloat(index + 1) / CGFloat(count) - halfGap)
                        .stroke(index == activeEntryIndex ? color : neutral, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PathNodePressStyle: ButtonStyle {
    let base: Color
    let diameter: CGFloat
    let count: Int
    let haloColor: Color
    let emphasized: Bool
    let activeEntryIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            if count > 1 || emphasized {
                DayEntryHalo(count: max(1, count), color: haloColor, diameter: diameter,
                             activeEntryIndex: activeEntryIndex ?? (emphasized ? 0 : nil))
            }
            configuration.label
                .offset(y: configuration.isPressed ? 6 : 0)
                .background(base, in: Ellipse().offset(y: 8))
                .offset(y: -4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }
}

extension PathNode {
    var routeIcon: String { routeTopic.symbolName }

    /// Read-only display matching, with source passages retaining a proposal's
    /// topic when the user gives the path button a shorter personal title.
    var routeTopic: PathTopic {
        if vaccination != nil { return .vaccination }
        if kind == .medication { return .medication }
        if history != nil { return historicalTopic }
        let name = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        func named(_ terms: [String]) -> Bool { terms.contains { name.contains($0) } }

        if kind == .event {
            switch chapter {
            case 0: return .beginning
            case 1: return .childhood
            case 2: return .independence
            default:
                if named(["spital", "krankenhaus", "hospital", "entlass", "discharge"]) { return .discharge }
                if named(["mein leben heute", "my life today"]) { return .present }
                return .event
            }
        }
        if kind == .information {
            return named(["entlass", "spital", "hospital", "discharge"]) ? .aftercare : .information
        }

        let source = evidence.map(\.quote).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        let topicText = name + " " + source
        func mentions(_ terms: [String]) -> Bool { terms.contains { topicText.contains($0) } }

        if mentions(["klaren", "klarung", "clarif", "wie besprochen"]) { return .clarification }
        if mentions(["physio", "bewegung", "physiotherapy"]) { return .therapy }
        if mentions(["nachkontrolle", "kontrolltermin", "follow-up", "follow up"]) { return .followUp }
        if mentions(["antrag", "formular", "entwurf", "application", "paperwork draft"]) { return .administration }
        if named(["anrufen", "telefon", "phone", "call"]) { return .phone }
        if kind == .appointment { return .appointment }
        if mentions(["unterlage", "dokument", "entlassungsbrief", "document", "paperwork"]) { return .documents }
        return .task
    }
}

private extension PathNode {
    var historicalTopic: PathTopic {
        let name = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        if name == "mein tag" { return .day }
        if name.contains("kostenerstattung") || name.contains("antrag") { return .administration }
        if history?.draftKind != nil || name.contains("anamnese") || name.contains("vorbereitung") { return .questionnaire }
        if name.contains("geburt") { return .beginning }
        if name.contains("screening") { return .screening }
        if name.contains("nach hause") || name.contains("entlass") { return .discharge }
        if name.contains("kinderarzt") { return .pediatrician }
        if name.contains("impf") || history?.category == .vaccination { return .vaccination }
        if name.contains("zahnarzt") || name.contains("mundhygiene") { return .dental }
        if name.contains("augen") || name.contains("sehtest") || name.contains("brille") { return .vision }
        if name.contains("schul") { return .school }
        if name.contains("versicherung") || name.contains("krankenstand") { return .insurance }
        if name.contains("e-card") { return .card }
        if name.contains("beruf") { return .work }
        if name.contains("physio") || history?.sessionNumber != nil { return .therapy }
        if name.contains("armbruch") || name.contains("gips") || name == "arm" || name.contains("rontgen") { return .fracture }
        if name.contains("medikament") || history?.category == .prescription || history?.category == .medicationEvidence { return .medication }
        if name.contains("ruckmeldung") || name.contains("verlauf") { return .feedback }
        if name.contains("infekt") || name.contains("grippe") || name.contains("magen") || name == "beschwerden" { return .infection }
        if name.contains("labor") { return .laboratory }
        if name.contains("rechnung") || name.contains("zahlung") { return .invoice }
        if name.contains("vorsorge") || name.contains("kontrolle") || name.contains("untersuchung") { return .followUp }
        if name.contains("ergebnisse") || history?.category == .finding { return .documents }
        if history?.category == .measurement { return .measurement }
        if history?.category == .form { return .questionnaire }
        if history?.category == .information { return .information }
        let dayName = history?.dayTitle.lowercased() ?? ""
        if dayName.contains("zahn") { return .dental }
        if dayName.contains("physio") { return .therapy }
        if dayName.contains("kinderarzt") { return .pediatrician }
        if dayName.contains("infekt") || dayName.contains("grippe") { return .infection }
        return kind == .appointment ? .appointment : kind == .task ? .task : .information
    }
}

private struct ToothSymbol: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.width * 0.5, y: r.height * 0.13))
            p.addCurve(to: CGPoint(x: r.width * 0.12, y: r.height * 0.46), control1: CGPoint(x: -r.width * 0.03, y: -r.height * 0.1), control2: CGPoint(x: r.width * 0.02, y: r.height * 0.27))
            p.addCurve(to: CGPoint(x: r.width * 0.3, y: r.height * 0.96), control1: CGPoint(x: r.width * 0.2, y: r.height * 0.61), control2: CGPoint(x: r.width * 0.19, y: r.height * 0.94))
            p.addCurve(to: CGPoint(x: r.width * 0.5, y: r.height * 0.58), control1: CGPoint(x: r.width * 0.43, y: r.height * 1.02), control2: CGPoint(x: r.width * 0.35, y: r.height * 0.58))
            p.addCurve(to: CGPoint(x: r.width * 0.7, y: r.height * 0.96), control1: CGPoint(x: r.width * 0.65, y: r.height * 0.58), control2: CGPoint(x: r.width * 0.57, y: r.height * 1.02))
            p.addCurve(to: CGPoint(x: r.width * 0.88, y: r.height * 0.46), control1: CGPoint(x: r.width * 0.81, y: r.height * 0.94), control2: CGPoint(x: r.width * 0.8, y: r.height * 0.61))
            p.addCurve(to: CGPoint(x: r.width * 0.5, y: r.height * 0.13), control1: CGPoint(x: r.width * 0.98, y: r.height * 0.27), control2: CGPoint(x: r.width * 1.03, y: -r.height * 0.1))
            p.closeSubpath()
        }
    }
}
