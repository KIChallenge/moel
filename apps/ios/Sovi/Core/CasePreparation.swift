import Foundation

struct CaseRecommendation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case rehabilitation, followUp, physiotherapy }
    var id: UUID
    var kind: Kind
    var evidence: EvidenceReference
    var reviewed = false
    var title: String {
        switch kind {
        case .rehabilitation: String(localized: "Reha-Antrag mit behandelnder Praxis vorbereiten")
        case .followUp: String(localized: "Nachkontrolltermin anfragen")
        case .physiotherapy: String(localized: "Verordnete Physiotherapie organisieren")
        }
    }
}

/// A deliberately small phrase recognizer for the demonstration. It never reads
/// diagnoses or derives care needs; candidates require explicit source review.
enum DischargeNavigationExtractor {
    static func recommendations(in document: SourceDocument) -> [CaseRecommendation] {
        let rules: [(CaseRecommendation.Kind, String)] = [
            (.rehabilitation, #"(?:Eine ambulante Rehabilitation wird empfohlen\.|Wir empfehlen eine ambulante Rehabilitation\.|Outpatient rehabilitation is recommended\.)"#),
            (.followUp, #"(?:Eine (?:(?:ärztliche|aerztliche) )?Nachkontrolle soll vereinbart werden\.|Eine (?:ärztliche )?Nachkontrolle wird empfohlen\.|A medical follow-up appointment should be arranged\.)"#),
            (.physiotherapy, #"(?:Physiotherapie wird empfohlen\.|Eine Physiotherapie wird empfohlen\.|Physiotherapy is recommended\.)"#)
        ]
        let text = document.text as NSString
        var found: [CaseRecommendation] = []
        for (kind, phrase) in rules {
            let pattern = #"(?:^|\n|(?<=[.!?])\s+)("# + phrase + ")"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: document.text, range: NSRange(location: 0, length: text.length)) else { continue }
            let range = match.range(at: 1)
            let quote = text.substring(with: range)
            let page = document.pageSpans?.first(where: { range.location >= $0.utf16Start && NSMaxRange(range) <= $0.utf16Start + $0.utf16Length })?.pageNumber
            let evidence = EvidenceReference(documentID: document.id, documentTitle: document.title,
                locator: page.map { String(localized: "Seite \($0)") } ?? String(localized: "Originaltext"), quote: quote, pageNumber: page)
            found.append(CaseRecommendation(id: LifePathSeed.stableID(document.id.uuidString + kind.rawValue + quote), kind: kind, evidence: evidence))
        }
        return found
    }
}

struct CasePreparation: Codable, Equatable, Sendable {
    var answers: [String: String] = [:]
    var applicantID: UUID?
    var sourceDocumentID: UUID?
    var recommendations: [CaseRecommendation] = []
    var checkedDocuments: Set<String> = []

    struct Question {
        var key: String
        var text: String
        var choices: [(String, String)]
    }
    func nextQuestion(for progress: DemoScenarioProgress) -> Question? {
        guard progress.scenario == .care, progress.finished else { return nil }
        if progress.answers.first != "home" {
            if answers["purpose"] == nil {
                return Question(key: "purpose", text: String(localized: "Geht es um einen ersten Pflegegeldantrag oder eine Erhöhung?"), choices: [
                    ("first", String(localized: "Erster Antrag")), ("increase", String(localized: "Erhöhung")), ("unknown", String(localized: "Noch unklar"))])
            }
            if answers["payer"] == nil {
                let prompt = answers["purpose"] == "increase" ? String(localized: "Welche Stelle zahlt ihr bisheriges Pflegegeld? Schau auf den letzten Bescheid.") : String(localized: "Wer zahlt ihre Pension? Gemeint ist der Pensionsträger, nicht die Krankenkasse.")
                return Question(key: "payer", text: prompt, choices: [
                    ("pv", "PV"), ("svs", "SVS"), ("bvaeb", "BVAEB"),
                    ("none", String(localized: "Keine Pension oder kein bisheriger Bezug")),
                    ("unknown", String(localized: "Andere Stelle oder Sonderfall"))])
            }
        }
        if answers["role"] == nil {
            return Question(key: "role", text: String(localized: "Wer wird den Antrag prüfen und unterschreiben?"), choices: [
                ("applicant", String(localized: "Meine Mutter selbst")),
                ("representative", String(localized: "Eine vertretungsbefugte Person")),
                ("helper", String(localized: "Ich helfe nur beim Vorbereiten")),
                ("unknown", String(localized: "Das müssen wir noch klären"))])
        }
        if answers["reports"] == nil {
            return Question(key: "reports", text: String(localized: "Sind aktuelle ärztliche Befunde oder ein Entlassungsbrief vorhanden?"), choices: [
                ("yes", String(localized: "Ja, Unterlagen sind vorhanden")),
                ("no", String(localized: "Nein, derzeit nicht")),
                ("unknown", String(localized: "Ich muss nachsehen"))])
        }
        return nil
    }

    static let authoritySource = "https://www.oesterreich.gv.at/de/themen/pflege/4/Seite.360515"
    static let applicationSource = "https://www.oesterreich.gv.at/de/themen/pflege/4/1/Seite.360517"
    var careAuthority: String? {
        if answers["purpose"] == "increase" && answers["payer"] == "none" { return nil }
        switch answers["payer"] {
        case "pv": return "Pensionsversicherung (PV)"
        case "svs": return "Sozialversicherung der Selbständigen (SVS)"
        case "bvaeb": return "BVAEB"
        case "none" where answers["purpose"] == "first": return "Pensionsversicherung (PV)"
        default: return nil
        }
    }
    func formIDs(for progress: DemoScenarioProgress) -> [String] {
        if progress.scenario == .hospital {
            return recommendations.contains { $0.reviewed && $0.kind == .rehabilitation } ? ["kur-reha"] : []
        }
        guard progress.scenario == .care else { return [] }
        var forms: [String] = []
        if progress.answers.first != "home", careAuthority == "Pensionsversicherung (PV)" { forms.append("pflegegeld") }
        if progress.answers.first != "money", ["wien", "vienna"].contains(progress.answers.dropFirst().first?.lowercased() ?? "") { forms.append("fsw-foerderung") }
        return forms
    }
    struct DocumentItem: Identifiable {
        var id: String
        var title: String
        var detail: String
    }
    func documentItems(for progress: DemoScenarioProgress) -> [DocumentItem] {
        var items: [DocumentItem] = []
        if progress.scenario == .hospital {
            items.append(.init(id: "source-reviewed", title: String(localized: "Originalbrief und Empfehlungen geprüft"), detail: String(localized: "Die Quelle bleibt mit den nächsten Schritten verbunden.")))
            if recommendations.contains(where: { $0.reviewed && $0.kind == .rehabilitation }) {
                items.append(.init(id: "practice", title: String(localized: "Ärztlichen Antragsteil mit der Praxis klären"), detail: String(localized: "Medizinische Angaben und Unterschrift werden nicht von Sovi erstellt.")))
                items.append(.init(id: "carrier", title: String(localized: "Zuständigen Reha-Träger mit der Praxis klären"), detail: String(localized: "Die gespeicherte Krankenkasse wird nicht als zuständiger Reha-Träger übernommen.")))
            }
        } else {
            if answers["reports"] != "no" {
                items.append(.init(id: "reports", title: String(localized: "Vorhandene aktuelle Befunde bereitlegen"), detail: String(localized: "Falls vorhanden: Kopien beilegen. Fehlende Befunde werden nicht erfunden.")))
            }
            if answers["purpose"] == "increase" {
                items.append(.init(id: "decision", title: String(localized: "Letzten Pflegegeldbescheid bereitlegen"), detail: String(localized: "Daraus die bisher zuständige Stelle übernehmen.")))
            }
            if ["svs", "bvaeb"].contains(answers["payer"] ?? "") {
                items.append(.init(id: "external-form", title: String(localized: "Passenden Antrag des zuständigen Trägers vorbereiten"), detail: String(localized: "Das offizielle Formular verwenden; die beigefügte PV-Vorlage ist dafür nicht bestimmt.")))
            }
            if answers["role"] == "representative" {
                items.append(.init(id: "representation", title: String(localized: "Vertretungsnachweis prüfen"), detail: String(localized: "Falls die Vertretung noch nicht bekannt ist: den passenden Nachweis beilegen.")))
            }
            if progress.answers.first != "money", ["wien", "vienna"].contains(progress.answers.dropFirst().first?.lowercased() ?? "") {
                items += [.init(id: "identity", title: String(localized: "Ausweis und Staatsbürgerschafts- oder Aufenthaltsnachweis"), detail: String(localized: "Für den FSW-Antrag laut Abschnitt Nötige Unterlagen.")),
                          .init(id: "income", title: String(localized: "Einkommens- und gegebenenfalls Wohnkostennachweise"), detail: String(localized: "Für Pflege und Betreuung: die im FSW-Formular genannten Nachweise prüfen."))]
            }
        }
        items.append(.init(id: "signatures", title: String(localized: "Offene Auswahlfelder, Erklärungen und Unterschrift prüfen"), detail: String(localized: "Persönliche Prüfung außerhalb der automatischen Vorbefüllung; keine Einreichung durch Sovi.")))
        return items
    }
    static func missingProfileFields(_ person: FormPerson?) -> [String] {
        let required: [PersonField] = [.firstName, .lastName, .birthDate, .street, .house, .postcode, .city]
        return required.filter { person?.values[$0.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }.map(\.title)
    }
}

extension AppState {
    func missingCaseItems(_ scenario: DemoScenario) -> [String] {
        guard let progress = demoScenarios?[scenario.rawValue] else { return [] }
        guard progress.finished else { return [progress.question] }
        let prep = progress.preparation ?? CasePreparation()
        var items: [String] = []
        if let question = prep.nextQuestion(for: progress) { items.append(question.text) }
        if scenario == .care, progress.answers.first != "home", prep.careAuthority == nil { items.append(String(localized: "Zuständige Stelle klären")) }
        if scenario == .care, prep.answers["purpose"] == "unknown" { items.append(String(localized: "Antragsart mit der zuständigen Stelle klären")) }
        if scenario == .care, prep.answers["role"] == "unknown" { items.append(String(localized: "Unterschrift und Vertretung klären")) }
        if scenario == .hospital, !prep.recommendations.contains(where: \.reviewed) { items.append(String(localized: "Empfehlung im Original prüfen und bestätigen")) }
        let person = formPeople?.first { $0.id == prep.applicantID }
        if !CasePreparation.missingProfileFields(person).isEmpty { items.append(String(localized: "Angaben der Person im Antrag ergänzen")) }
        for doc in prep.documentItems(for: progress) where !prep.checkedDocuments.contains(doc.id) { items.append(doc.title) }
        for formID in prep.formIDs(for: progress) {
            let key = prep.applicantID.map { formID + ":" + $0.uuidString }
            let draft = key.flatMap { formDrafts?[$0] }
            if draft?.caseScenario != scenario.rawValue { items.append(String(localized: "Formularentwurf speichern: \(formID)")) }
            else if formID == "pflegegeld", let kind = prep.answers["purpose"], ["first", "increase"].contains(kind), draft?.selections?["Antrag Pflg"] != (kind == "first" ? "01" : "02") {
                items.append(String(localized: "Antragsart im gespeicherten Entwurf prüfen"))
            }
        }
        if !progress.saved { items.append(String(localized: "Nächste Schritte auf dem Pfad speichern")) }
        else {
            for index in progress.steps.indices {
                if let node = nodes.first(where: { $0.id == progress.taskID(index) }), ![TaskStatus.completed, .cancelled].contains(node.taskStatus) { items.append(node.title) }
            }
        }
        return items
    }
}
