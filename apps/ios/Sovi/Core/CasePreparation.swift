import Foundation

struct CaseRecommendation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case rehabilitation, followUp, physiotherapy }
    var id: UUID
    var kind: Kind
    var evidence: EvidenceReference
    var reviewed = false
    var title: String { title(in: .app) }
    func title(in language: ChatLanguage) -> String {
        switch kind {
        case .rehabilitation: language.text("Reha-Antrag mit behandelnder Praxis vorbereiten")
        case .followUp: language.text("Nachkontrolltermin anfragen")
        case .physiotherapy: language.text("Verordnete Physiotherapie organisieren")
        }
    }
}

/// A deliberately small phrase recognizer for the demonstration. It never reads
/// diagnoses or derives care needs; candidates require explicit source review.
enum DischargeNavigationExtractor {
    static func recommendations(in document: SourceDocument) -> [CaseRecommendation] {
        let reportActions = BefundReader.caseRecommendations(in: document)
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
        // Preserve pending reviews from earlier app versions, including their
        // persisted IDs and punctuation, and recognize additional report layouts.
        guard let reportActions else { return found }
        return reportActions.map { candidate in
            found.first { $0.kind == candidate.kind && $0.evidence.quote == candidate.evidence.quote } ?? candidate
        }
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

        /// Accept the button label, a stable code, or one unambiguous natural answer.
        func answerID(_ message: String) -> String? {
            let t = ChatLanguage.normalized(message).trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = choices.first(where: { $0.0 == t || ChatLanguage.normalized($0.1) == t }) { return exact.0 }
            let aliases: [String: [String]]
            switch key {
            case "purpose": aliases = ["first": ["erst", "first", "ilk", "أول"], "increase": ["erhoh", "increase", "artis", "زياد"]]
            case "payer": aliases = ["pv": ["pensionsversicherung", "pva", "pv"], "svs": ["svs"], "bvaeb": ["bvaeb"], "none": ["keine pension", "no pension", "emekli degil", "لا يوجد معاش"]]
            case "role": aliases = ["applicant": ["selbst", "herself", "kendisi", "بنفسها"], "representative": ["vertretungsbefugt", "authorized representative", "yetkili temsilci", "ممثل مفوض"], "helper": ["helfe nur", "only helping", "just helping", "sadece yardim", "اساعد فقط"]]
            case "reports": aliases = ["yes": ["ja", "yes", "evet", "نعم"], "no": ["nein", "no", "hayir", "لا"]]
            default: aliases = [:]
            }
            let uncertain = ["weiß nicht", "weiss nicht", "nicht sicher", "don't know", "not sure", "bilmiyorum", "emin degil", "لا اعرف", "لا أعرف"]
            if uncertain.contains(where: t.contains) { return choices.contains(where: { $0.0 == "unknown" }) ? "unknown" : nil }
            let matches = choices.filter { choice in
                (aliases[choice.0] ?? []).contains { phrase in
                    let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: ChatLanguage.normalized(phrase))
                    return t.range(of: pattern, options: .regularExpression) != nil
                }
            }
            return matches.count == 1 ? matches[0].0 : nil
        }
    }
    func nextQuestion(for progress: DemoScenarioProgress) -> Question? {
        guard progress.scenario == .care, progress.finished else { return nil }
        if progress.answers.first != "home" {
            if answers["purpose"] == nil {
                return Question(key: "purpose", text: progress.replyLanguage.text("Geht es um einen ersten Pflegegeldantrag oder eine Erhöhung?"), choices: [
                    ("first", progress.replyLanguage.text("Erster Antrag")), ("increase", progress.replyLanguage.text("Erhöhung")), ("unknown", progress.replyLanguage.text("Noch unklar"))])
            }
            if answers["payer"] == nil {
                let prompt = answers["purpose"] == "increase" ? progress.replyLanguage.text("Welche Stelle zahlt ihr bisheriges Pflegegeld? Schau auf den letzten Bescheid.") : progress.replyLanguage.text("Wer zahlt ihre Pension? Gemeint ist der Pensionsträger, nicht die Krankenkasse.")
                return Question(key: "payer", text: prompt, choices: [
                    ("pv", "PV"), ("svs", "SVS"), ("bvaeb", "BVAEB"),
                    ("none", progress.replyLanguage.text("Keine Pension oder kein bisheriger Bezug")),
                    ("unknown", progress.replyLanguage.text("Andere Stelle oder Sonderfall"))])
            }
        }
        if answers["role"] == nil {
            return Question(key: "role", text: progress.replyLanguage.text("Wer wird den Antrag prüfen und unterschreiben?"), choices: [
                ("applicant", progress.replyLanguage.text("Meine Mutter selbst")),
                ("representative", progress.replyLanguage.text("Eine vertretungsbefugte Person")),
                ("helper", progress.replyLanguage.text("Ich helfe nur beim Vorbereiten")),
                ("unknown", progress.replyLanguage.text("Das müssen wir noch klären"))])
        }
        if answers["reports"] == nil {
            return Question(key: "reports", text: progress.replyLanguage.text("Sind aktuelle ärztliche Befunde oder ein Entlassungsbrief vorhanden?"), choices: [
                ("yes", progress.replyLanguage.text("Ja, Unterlagen sind vorhanden")),
                ("no", progress.replyLanguage.text("Nein, derzeit nicht")),
                ("unknown", progress.replyLanguage.text("Ich muss nachsehen"))])
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
        if progress.answers.first != "money", progress.careInVienna { forms.append("fsw-foerderung") }
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
            items.append(.init(id: "source-reviewed", title: progress.replyLanguage.text("Originalbrief und Empfehlungen geprüft"), detail: progress.replyLanguage.text("Die Quelle bleibt mit den nächsten Schritten verbunden.")))
            if recommendations.contains(where: { $0.reviewed && $0.kind == .rehabilitation }) {
                items.append(.init(id: "practice", title: progress.replyLanguage.text("Ärztlichen Antragsteil mit der Praxis klären"), detail: progress.replyLanguage.text("Medizinische Angaben und Unterschrift werden nicht von Sovi erstellt.")))
                items.append(.init(id: "carrier", title: progress.replyLanguage.text("Zuständigen Reha-Träger mit der Praxis klären"), detail: progress.replyLanguage.text("Die gespeicherte Krankenkasse wird nicht als zuständiger Reha-Träger übernommen.")))
            }
        } else {
            if answers["reports"] != "no" {
                items.append(.init(id: "reports", title: progress.replyLanguage.text("Vorhandene aktuelle Befunde bereitlegen"), detail: progress.replyLanguage.text("Falls vorhanden: Kopien beilegen. Fehlende Befunde werden nicht erfunden.")))
            }
            if answers["purpose"] == "increase" {
                items.append(.init(id: "decision", title: progress.replyLanguage.text("Letzten Pflegegeldbescheid bereitlegen"), detail: progress.replyLanguage.text("Daraus die bisher zuständige Stelle übernehmen.")))
            }
            if ["svs", "bvaeb"].contains(answers["payer"] ?? "") {
                items.append(.init(id: "external-form", title: progress.replyLanguage.text("Passenden Antrag des zuständigen Trägers vorbereiten"), detail: progress.replyLanguage.text("Das offizielle Formular verwenden; die beigefügte PV-Vorlage ist dafür nicht bestimmt.")))
            }
            if answers["role"] == "representative" {
                items.append(.init(id: "representation", title: progress.replyLanguage.text("Vertretungsnachweis prüfen"), detail: progress.replyLanguage.text("Falls die Vertretung noch nicht bekannt ist: den passenden Nachweis beilegen.")))
            }
            if progress.answers.first != "money", progress.careInVienna {
                items += [.init(id: "identity", title: progress.replyLanguage.text("Ausweis und Staatsbürgerschafts- oder Aufenthaltsnachweis"), detail: progress.replyLanguage.text("Für den FSW-Antrag laut Abschnitt Nötige Unterlagen.")),
                          .init(id: "income", title: progress.replyLanguage.text("Einkommens- und gegebenenfalls Wohnkostennachweise"), detail: progress.replyLanguage.text("Für Pflege und Betreuung: die im FSW-Formular genannten Nachweise prüfen."))]
            }
        }
        items.append(.init(id: "signatures", title: progress.replyLanguage.text("Offene Auswahlfelder, Erklärungen und Unterschrift prüfen"), detail: progress.replyLanguage.text("Persönliche Prüfung außerhalb der automatischen Vorbefüllung; keine Einreichung durch Sovi.")))
        return items
    }
    static func missingProfileFields(_ person: FormPerson?, language: ChatLanguage = .app) -> [String] {
        let required: [PersonField] = [.firstName, .lastName, .birthDate, .street, .house, .postcode, .city]
        return required.filter { person?.values[$0.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }.map { $0.title(in: language) }
    }
}

extension AppState {
    func missingCaseItems(_ scenario: DemoScenario, language: ChatLanguage? = nil) -> [String] {
        guard var progress = demoScenarios?[scenario.rawValue] else { return [] }
        if let language { progress.language = language }
        guard progress.finished else { return [progress.question] }
        let prep = progress.preparation ?? CasePreparation()
        var items: [String] = []
        if let question = prep.nextQuestion(for: progress) { items.append(question.text) }
        if scenario == .care, progress.answers.first != "home", prep.careAuthority == nil { items.append(progress.replyLanguage.localized("Zuständige Stelle klären")) }
        if scenario == .care, prep.answers["purpose"] == "unknown" { items.append(progress.replyLanguage.localized("Antragsart mit der zuständigen Stelle klären")) }
        if scenario == .care, prep.answers["role"] == "unknown" { items.append(progress.replyLanguage.localized("Unterschrift und Vertretung klären")) }
        if scenario == .hospital, !prep.recommendations.contains(where: \.reviewed) { items.append(progress.replyLanguage.localized("Empfehlung im Original prüfen und bestätigen")) }
        let person = formPeople?.first { $0.id == prep.applicantID }
        if !CasePreparation.missingProfileFields(person).isEmpty { items.append(progress.replyLanguage.localized("Angaben der Person im Antrag ergänzen")) }
        for doc in prep.documentItems(for: progress) where !prep.checkedDocuments.contains(doc.id) { items.append(doc.title) }
        for formID in prep.formIDs(for: progress) {
            let key = prep.applicantID.map { formID + ":" + $0.uuidString }
            let draft = key.flatMap { formDrafts?[$0] }
            if draft?.caseScenario != scenario.rawValue { items.append(progress.replyLanguage.localized("Formularentwurf speichern: \(formID)")) }
            else if formID == "pflegegeld", let kind = prep.answers["purpose"], ["first", "increase"].contains(kind), draft?.selections?["Antrag Pflg"] != (kind == "first" ? "01" : "02") {
                items.append(progress.replyLanguage.localized("Antragsart im gespeicherten Entwurf prüfen"))
            }
        }
        if !progress.saved { items.append(progress.replyLanguage.localized("Nächste Schritte auf dem Pfad speichern")) }
        else {
            for index in progress.steps.indices {
                if let node = nodes.first(where: { $0.id == progress.taskID(index) }), ![TaskStatus.completed, .cancelled].contains(node.taskStatus) { items.append(node.title) }
            }
        }
        return items
    }
}
