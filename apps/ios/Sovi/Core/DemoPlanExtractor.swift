import Foundation

protocol PlanExtractor {
    func extract(document: SourceDocument, anchor: Date, calendar: Calendar) throws -> [PlanProposal]
}

/// An explicit fixture matcher, not a general-purpose medical text interpreter.
struct DemoPlanExtractor: PlanExtractor {
    func extract(document: SourceDocument, anchor: Date, calendar: Calendar) throws -> [PlanProposal] {
        let text = Self.normalized(document.text)
        let fixtureA = try DemoFixtures.text("A", anchor: anchor, calendar: calendar)
        let fixtureB = try DemoFixtures.text("B", anchor: anchor, calendar: calendar)
        if text == Self.normalized(fixtureA) {
            let paragraphs = fixtureA.components(separatedBy: "\n\n")
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: anchor)!)
            let end = calendar.date(byAdding: .day, value: 2, to: start)!
            let medicationEvidence = evidence(document: document, paragraph: paragraphs[2], index: 3)
            return [
                PlanProposal(
                    title: "Demo-Medikamentenplan",
                    detail: "Zeitplan prüfen.",
                    kind: .medication,
                    evidence: [medicationEvidence],
                    medicationInstruction: paragraphs[2],
                    medicationStart: start,
                    medicationEnd: end
                ),
                PlanProposal(
                    title: "Physiotherapie organisieren · 6 Einheiten",
                    detail: "6 Einheiten organisieren.",
                    kind: .task,
                    evidence: [evidence(document: document, paragraph: paragraphs[3], index: 4)]
                ),
                PlanProposal(
                    title: "Nachkontrolle organisieren",
                    detail: "Datum noch offen.",
                    kind: .task,
                    evidence: [evidence(document: document, paragraph: paragraphs[4], index: 5)]
                )
            ]
        }
        if text == Self.normalized(fixtureB) {
            let quote = "Medikation wie besprochen fortführen"
            return [PlanProposal(
                title: "Medikationsanweisung klären",
                detail: "Dosis, Zeiten und Dauer fehlen.",
                kind: .clarification,
                evidence: [evidence(document: document, paragraph: quote, index: 3)]
            )]
        }
        // Fixture C and all unknown inputs deliberately produce no care plan.
        return []
    }

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func evidence(document: SourceDocument, paragraph: String, index: Int) -> EvidenceReference {
        EvidenceReference(documentID: document.id, documentTitle: document.title,
                          locator: "Absatz \(index)", quote: paragraph)
    }
}

enum DemoFixtures {
    static let identifiers = ["A", "B", "C"]

    static func title(_ id: String) -> String {
        switch id.uppercased() {
        case "A": "Entlassungsbrief"
        case "B": "Medikationsangaben"
        default: "Weitere Unterlage"
        }
    }

    static func text(_ id: String, anchor: Date, calendar: Calendar) throws -> String {
        let identifier = id.uppercased()
        guard identifiers.contains(identifier) else { throw SoviError.invalidAction }
        let resource = "demo-\(identifier.lowercased())"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt", subdirectory: "Fixtures")
            ?? Bundle.main.url(forResource: resource, withExtension: "txt") else {
            throw SoviError.invalidInput(String(localized: "Unterlage nicht verfügbar."))
        }
        let template = try String(contentsOf: url, encoding: .utf8)
        let start = calendar.date(byAdding: .day, value: 1, to: anchor)!
        let end = calendar.date(byAdding: .day, value: 3, to: anchor)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "de_AT")
        formatter.dateFormat = "dd.MM.yyyy"
        return template
            .replacingOccurrences(of: "{{discharge}}", with: formatter.string(from: anchor))
            .replacingOccurrences(of: "{{start}}", with: formatter.string(from: start))
            .replacingOccurrences(of: "{{end}}", with: formatter.string(from: end))
            .replacingOccurrences(of: "{{timezone}}", with: calendar.timeZone.identifier)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
