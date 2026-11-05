import Foundation

struct CompanionResponse {
    var text: String
    var evidence: [EvidenceReference] = []
    var action: CompanionAction?
    var caseChoices: [DemoScenario] = []
}

enum CompanionAction {
    case documents, draft, preparation(LifeDraftKind), add(NodeKind), preview(UUID), controls, scenario(DemoScenario)

    var title: String {
        switch self {
        case .documents: String(localized: "Dokumente öffnen")
        case .draft: String(localized: "Entwurf öffnen")
        case .preparation(.questionnaire): String(localized: "Anamnesebogen öffnen")
        case .preparation(.medicationList): String(localized: "Medikamentenliste öffnen")
        case .add(.appointment): String(localized: "Termin eintragen")
        case .add(.event): String(localized: "Ereignis hinzufügen")
        case .add: String(localized: "Aufgabe hinzufügen")
        case .preview: String(localized: "Eintrag öffnen")
        case .controls: String(localized: "Einstellungen")
        case .scenario: String(localized: "Vorgang fortsetzen")
        }
    }
}

protocol CompanionService {
    func respond(to message: String, context: UUID?, state: AppState, now: Date) -> CompanionResponse
}

/// Deterministic, offline intent matching. Never applies commands or interprets medicine.
struct DemoCompanionService: CompanionService {
    func respond(to message: String, context: UUID?, state: AppState, now: Date) -> CompanionResponse {
        if let savedCase = Self.savedCaseResponse(to: message, state: state) { return savedCase }
        let text = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        let selected = state.nodes.first { $0.id == context }
        let open = state.uniqueOpenTasks
        if contains(text, ["gespeichert", "daten", "datenschutz", "speicherst"]) {
            return CompanionResponse(text: String(localized: "Auf diesem Gerät: \(state.nodes.count) Einträge, \(state.documents.count) Dokumente und \(state.conversation.count) Nachrichten."), action: .controls)
        }
        if contains(text, ["entlass", "dokument", "brief", "anhang"]) {
            return CompanionResponse(text: String(localized: "Öffne ein Dokument, um die Einträge zu prüfen."), action: .documents)
        }
        if contains(text, ["warum", "quelle", "woher", "beleg"]) {
            guard let selected else {
                return CompanionResponse(text: String(localized: "Welchen Eintrag meinst du?"))
            }
            return CompanionResponse(text: selected.evidence.isEmpty
                ? String(localized: "Für „\(selected.displayTitle)“ ist keine Quelle hinterlegt.")
                : String(localized: "Hier findest du die Quelle zu „\(selected.displayTitle)“."), evidence: selected.evidence, action: .preview(selected.id))
        }
        if contains(text, ["impf", "vaccin"]) {
            let records = state.nodes.filter { $0.vaccination != nil }.sorted {
                if $0.date != $1.date { return ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                return $0.title < $1.title
            }
            guard let node = selected?.vaccination == nil ? records.first : selected,
                  let record = node.vaccination else {
                return CompanionResponse(text: String(localized: "Keine Impfungen eingetragen."))
            }
            if selected?.id == node.id {
                return CompanionResponse(text: String(localized: "\(record.disease): \(record.product), \(record.administrationText). \(record.doseLabel) · Charge \(record.batch)."), evidence: node.evidence, action: .preview(node.id))
            }
            let covid = records.filter { $0.vaccination?.disease == "COVID-19" }.count
            let influenza = records.filter { $0.vaccination?.disease == "Influenza" }.count
            let formatter = DateFormatter(); formatter.timeZone = state.pathCalendar.timeZone
            formatter.locale = .current; formatter.dateFormat = "d. MMMM yyyy"
            let latest = node.date.map(formatter.string(from:)) ?? record.administrationText
            return CompanionResponse(text: String(localized: "\(records.count) Impfungen: \(covid) COVID-19 und \(influenza) Influenza. Zuletzt am \(latest)."), evidence: node.evidence, action: .preview(node.id))
        }
        if contains(text, ["anamnese", "medikamentenliste"]) || (contains(text, ["formular", "vorsorge"]) && selected?.history?.draftKind != nil) {
            let kind: LifeDraftKind = contains(text, ["medikamentenliste"]) ? .medicationList : selected?.history?.draftKind ?? .questionnaire
            return CompanionResponse(text: String(localized: "Öffnen wir den Entwurf."), action: .preparation(kind))
        }
        if contains(text, ["antrag", "kostenerstatt", "formular", "papier", "entwurf"]) {
            return CompanionResponse(text: String(localized: "Ich helfe dir beim Entwurf."), action: .draft)
        }
        let creating = contains(text, ["eintragen", "anlegen", "hinzufugen", "organisieren", "vereinbaren", "erstellen"])
        if contains(text, ["termin", "physio", "therapie"]) && (creating || !contains(text, ["heute", "offen", "ansteht", "steht an"])) {
            return CompanionResponse(text: String(localized: "Welchen Termin möchtest du eintragen?"), action: .add(.appointment))
        }
        if contains(text, ["ereignis", "lebensereignis", "kapitel"]) {
            return CompanionResponse(text: String(localized: "Was möchtest du festhalten?"), action: .add(.event))
        }
        if creating && contains(text, ["aufgabe", "schritt"]) && !contains(text, ["erledigt", "fertig", "abgeschlossen"]) {
            return CompanionResponse(text: String(localized: "Welche Aufgabe möchtest du hinzufügen?"), action: .add(.task))
        }
        if contains(text, ["erledigt", "fertig", "abgeschlossen", "geschafft"]) {
            if let selected, selected.kind == .task {
                return CompanionResponse(text: String(localized: "Möchtest du „\(selected.displayTitle)“ als erledigt markieren?"), action: .preview(selected.id))
            }
            if open.count == 1, let first = open.first {
                return CompanionResponse(text: String(localized: "Möchtest du „\(first.displayTitle)“ als erledigt markieren?"), action: .preview(first.id))
            }
            return CompanionResponse(text: String(localized: "Welche Aufgabe meinst du? Offen: \(open.count)."))
        }
        if contains(text, ["heute", "offen", "ansteht", "ansteht", "zu tun", "steht an", "uberblick"]) {
            if let scenario = state.lifeScenario {
                let currentID = state.currentPathDayID
                let today = state.pathDays.first { $0.id == currentID }
                let summary = today?.entries.map { node -> String in
                    if let id = node.appointmentID, let appointment = state.appointments.first(where: { $0.id == id }) {
                        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: scenario.timeZone)
                        formatter.locale = .current; formatter.dateFormat = "HH:mm"
                        return "\(node.displayTitle) \(formatter.string(from: appointment.date))"
                    }
                    return node.kind == .task ? "\(node.displayTitle) · \(node.taskStatus.displayTitle)" : node.displayTitle
                }.joined(separator: "; ") ?? String(localized: "Keine Einträge")
                let planned = state.appointments.filter { $0.status != .cancelled && $0.attendance == .unrecorded && $0.date >= scenario.snapshot }.count
                let unrecorded = state.schedules.flatMap(\.occurrences).filter { $0.log == .unrecorded }.count
                var reply = String(localized: "Heute: \(summary).\nOffene Aufgaben: \(open.count) · Termine: \(planned)")
                if unrecorded > 0 { reply += "\n" + String(localized: "Einnahmen offen: \(unrecorded)") }
                return CompanionResponse(text: reply, action: open.first.map { .preview($0.id) })
            }
            let appointments = state.appointments.filter { $0.status != .cancelled && $0.date >= now }
            let unrecorded = state.schedules.flatMap(\.occurrences).filter { $0.log == .unrecorded }.count
            var reply = String(localized: "Offene Aufgaben: \(open.count) · Termine: \(appointments.count)")
            if unrecorded > 0 { reply += "\n" + String(localized: "Einnahmen offen: \(unrecorded)") }
            return CompanionResponse(text: reply, action: open.first.map { .preview($0.id) })
        }
        if contains(text, ["medikament", "dosis", "schmerz", "diagnose", "behandlung", "notfall"]) {
            return CompanionResponse(text: String(localized: "Bitte kläre medizinische Fragen mit deiner behandelnden Stelle."))
        }
        return CompanionResponse(text: String(localized: "Wobei kann ich dir helfen? Aufgaben, Termine oder Unterlagen?"))
    }

    static func savedCaseResponse(to message: String, state: AppState) -> CompanionResponse? {
        let text = message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        if let other = DemoScenario.matching(message), ![DemoScenario.care, .hospital].contains(other) { return nil }
        let isProgress = ["fehlt", "fehlen", "fortsetzen", "missing", "continue", "progress", "status", "antragsstand"].contains(where: text.contains)
            || text.range(of: #"\bstand\b"#, options: .regularExpression) != nil
            || (text.contains("weiter") && ["antrag", "vorgang", "mutter", "reha"].contains(where: text.contains))
        guard isProgress else { return nil }
        let choices = [DemoScenario.care, .hospital].filter { state.demoScenarios?[$0.rawValue] != nil }
        let care = ["mutter", "pflegegeld", "mother", "mum", "mom"].contains(where: text.contains)
        let hospital = ["reha", "nachsorge", "spital", "entlass", "hospital", "discharge"].contains(where: text.contains)
        let selected = care && !hospital ? DemoScenario.care : hospital && !care ? .hospital : choices.count == 1 ? choices.first : nil
        guard let selected, state.demoScenarios?[selected.rawValue] != nil else {
            guard !choices.isEmpty else { return nil }
            return CompanionResponse(text: String(localized: "Welchen Vorgang möchtest du fortsetzen?"), caseChoices: choices)
        }
        let missing = state.missingCaseItems(selected)
        let next = missing.first ?? String(localized: "Vorbereitung prüfen und den offiziellen Weg zur Einreichung öffnen.")
        return CompanionResponse(text: String(localized: "\(selected.title): \(missing.count) Vorbereitungspunkte offen. Als Nächstes: \(next)"), action: .scenario(selected))
    }

    private func contains(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}
