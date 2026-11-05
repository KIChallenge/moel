import Foundation

enum DemoScenario: String, Codable, CaseIterable, Identifiable, Sendable {
    case care, hospital, health, child
    var id: String { rawValue }
    var title: String {
        switch self {
        case .care: String(localized: "Hilfe für meine Mutter")
        case .hospital: String(localized: "Nach dem Spital")
        case .health: String(localized: "Etwas für meine Gesundheit tun")
        case .child: String(localized: "Angebote für mein Kind")
        }
    }
    static func matching(_ text: String) -> Self? {
        let t = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        if ["mutter", "mother", "mum", "mom"].contains(where: t.contains) && ["hilfe", "help", "allein", "alone", "pflege", "support"].contains(where: t.contains) { return .care }
        if ["nach dem spital", "nach dem krankenhaus", "after hospital", "discharge letter", "entlassungsbrief bekommen"].contains(where: t.contains) { return .hospital }
        if ["gesundheit tun", "healthier", "improve my health", "health promotion", "gesundheitsforderung"].contains(where: t.contains) { return .health }
        if ["mein kind", "my child"].contains(where: t.contains) && ["angebot", "offers", "support", "wissen", "services"].contains(where: t.contains) { return .child }
        return nil
    }
}

struct DemoScenarioProgress: Codable, Equatable, Sendable {
    var scenario: DemoScenario
    var answers: [String] = []
    var history: [ConversationTurn] = []
    var saved = false
    var preparation: CasePreparation?
    var finished: Bool { answers.count >= (scenario == .health ? 1 : 2) }
    var question: String {
        switch scenario {
        case .care: answers.isEmpty ? String(localized: "Was braucht deine Mutter gerade: Hilfe zu Hause, finanzielle Unterstützung oder beides?") : String(localized: "In welchem Ort lebt deine Mutter? Dein Standort muss nicht ihr Wohnort sein.")
        case .hospital: answers.isEmpty ? String(localized: "Was wurde im Entlassungsbrief ausdrücklich empfohlen? Du kannst einen Satz abschreiben oder den fiktiven Beispielbrief verwenden.") : String(localized: "Wann hättest du am liebsten einen Termin? Das ist ein Wunsch, noch keine Buchung.")
        case .health: String(localized: "Was interessiert dich: Vorsorge, Bewegung oder Ernährung?")
        case .child: answers.isEmpty ? String(localized: "Wie alt ist dein Kind? Es reicht eine Zahl in Jahren.") : String(localized: "Welche Angebote suchst du für dein Kind?")
        }
    }
    var choices: [String] {
        guard !finished else { return [] }
        return switch scenario {
        case .care: answers.isEmpty ? [String(localized: "Hilfe zu Hause"), String(localized: "Pflegegeld vorbereiten"), String(localized: "Beides")] : ["Wien", "Graz", "Linz"]
        case .hospital: answers.isEmpty ? [String(localized: "Fiktiven Beispielbrief verwenden")] : [String(localized: "Vormittags"), String(localized: "Nachmittags"), String(localized: "Zeitlich flexibel")]
        case .health: [String(localized: "Vorsorge"), String(localized: "Bewegung"), String(localized: "Ernährung")]
        case .child: answers.isEmpty ? ["2", "8", "14"] : [String(localized: "Vorsorge"), String(localized: "Familienberatung"), String(localized: "Bewegung")]
        }
    }
    static var sampleLetter: String { String(localized: "Fiktiver Beispielbrief: Eine ambulante Rehabilitation wird empfohlen. Eine ärztliche Nachkontrolle soll vereinbart werden.") }
    func normalizedAnswer(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 600 else { throw SoviError.invalidInput(String(localized: "Bitte kurz antworten (maximal 600 Zeichen).")) }
        if scenario == .hospital && answers.isEmpty {
            if text == String(localized: "Fiktiven Beispielbrief verwenden") { return Self.sampleLetter }
            let lower = text.lowercased()
            guard (lower.contains("empfohl") || lower.contains("recommended") || lower.contains("vereinbar")),
                  (lower.contains("rehab") || lower.contains("kontroll") || lower.contains("follow-up")) else {
                throw SoviError.invalidInput(String(localized: "Für diese Demo brauche ich eine ausdrückliche Empfehlung zu Rehabilitation oder Nachkontrolle. Oder verwende den fiktiven Beispielbrief."))
            }
        }
        if scenario == .child && answers.isEmpty {
            guard let age = Int(text), (0...17).contains(age) else { throw SoviError.invalidInput(String(localized: "Bitte das Alter als Zahl von 0 bis 17 eingeben.")) }
        }
        if answers.isEmpty && [.care, .health].contains(scenario) || scenario == .child && answers.count == 1 {
            guard choices.contains(text) else { throw SoviError.invalidInput(String(localized: "Wähle für diese Demo eine der Möglichkeiten. Andere Anliegen kannst du im normalen Chat stellen.")) }
        }
        if let index = choices.firstIndex(of: text) {
            if scenario == .care && answers.isEmpty { return ["home", "money", "both"][index] }
            if scenario == .health { return ["prevention", "movement", "nutrition"][index] }
            if scenario == .child && answers.count == 1 { return ["prevention", "family", "movement"][index] }
        }
        return text
    }
    var suggestedForm: String? {
        if let preparation, [.care, .hospital].contains(scenario) { return preparation.formIDs(for: self).first }
        if scenario == .hospital { return answers.first?.lowercased().contains("rehab") == true ? "kur-reha" : nil }
        if scenario == .care { return answers.first == "home" && answers.last?.lowercased() == "wien" ? "fsw-foerderung" : "pflegegeld" }
        return nil
    }
    var sources: [(String, String)] {
        switch scenario {
        case .care:
            if ["wien", "vienna"].contains(answers.last?.lowercased() ?? "") { return [("Fonds Soziales Wien", "https://www.fsw.at/p/pflege-betreuung"), (String(localized: "Pflegegeld und Antrag"), "https://www.pv.at/web/pflegegeld")] }
            return [(String(localized: "Pflegeberatung"), "https://pflege.gv.at/de/beratungsstellen-im-bundesland"), (String(localized: "Pflegegeld und Antrag"), "https://www.pv.at/web/pflegegeld")]
        case .hospital: return [(String(localized: "Rehabilitation organisieren"), "https://www.gesundheit.gv.at/gesundheitsleistungen/kur-reha/medizinische-rehabilitation.html"), (String(localized: "Einrichtungen suchen"), "https://rehakompass.goeg.at/")]
        case .health:
            if answers.first == "movement" { return [("Bewegt im Park", "https://www.bewegt-im-park.at/")] }
            if answers.first == "nutrition" { return [(String(localized: "Ernährung"), "https://www.gesundheit.gv.at/leben/ernaehrung.html")] }
            return [(String(localized: "Vorsorgeuntersuchung"), "https://www.gesundheit.gv.at/leben/gesundheitsvorsorge/vorsorgeuntersuchung.html")]
        case .child:
            if answers.last == "family" { return [(String(localized: "Beratungsstellen finden"), "https://www.familienberatung.gv.at/beratungsstellen.html")] }
            if answers.last == "movement" { return [("Bewegt im Park", "https://www.bewegt-im-park.at/")] }
            if let age = answers.first.flatMap(Int.init), age >= 6 { return [(String(localized: "Gesundheitsportal"), "https://www.gesundheit.gv.at/")] }
            return [(String(localized: "Kindesuntersuchungen"), "https://www.gesundheit.gv.at/leben/eltern/eltern-kind-pass/kindesuntersuchungen.html")]
        }
    }
    var summary: String {
        switch scenario {
        case .care: String(localized: "Wir können Beratung und einen passenden Antragsentwurf vorbereiten. Ein Anspruch oder eine Pflegestufe wird hier nicht festgestellt.")
        case .hospital: String(localized: "Wir organisieren nur die ausdrücklich genannte Empfehlung. Die ärztlichen Teile des Reha-Antrags bleiben offen.")
        case .health: String(localized: "Hier ist dein nächster organisatorischer Schritt. Passende medizinische Vorsorge besprichst du mit deiner Praxis. Bewegungskurse sind saisonal; aktuelle Termine bitte auf der Angebotsseite prüfen.")
        case .child: String(localized: "Wir sammeln Angebote und bereiten deine Fragen vor. Es wird kein Untersuchungs- oder Impfbedarf aus dem Alter abgeleitet.")
        }
    }
    var steps: [String] {
        switch scenario {
        case .care:
            if answers.first == "home" { return [String(localized: "Regionale Pflegeberatung kontaktieren"), String(localized: "Mobile Hilfe und benötigte Unterlagen besprechen")] }
            if answers.first == "money" { return [String(localized: "Zuständige Stelle für Pflegegeld klären"), String(localized: "Vorhandene Unterlagen sammeln"), String(localized: "Pflegegeld-Entwurf prüfen") ] }
            return [String(localized: "Regionale Pflegeberatung kontaktieren"), String(localized: "Mobile Hilfe und benötigte Unterlagen besprechen"), String(localized: "Pflegegeld-Entwurf prüfen")]
        case .hospital:
            if let preparation, preparation.sourceDocumentID != nil {
                return [String(localized: "Empfehlung im Entlassungsbrief prüfen")] + preparation.recommendations.filter(\.reviewed).map(\.title)
            }
            let text = answers.first?.lowercased() ?? ""
            var list = [String(localized: "Empfehlung im Entlassungsbrief prüfen")]
            if text.contains("rehab") { list += [String(localized: "Reha-Antrag mit behandelnder Praxis vorbereiten")] }
            if text.contains("kontroll") || text.contains("follow-up") { list += [String(localized: "Nachkontrolltermin anfragen")] }
            return list
        case .health:
            if answers.first == "movement" { return [String(localized: "Aktuelle Bewegungskurse am gewünschten Ort prüfen"), String(localized: "Kurs auswählen und Termin selbst bestätigen")] }
            if answers.first == "nutrition" { return [String(localized: "Ernährungsangebote ansehen"), String(localized: "Fragen für eine Ernährungsberatung sammeln")] }
            return [String(localized: "Praxis nach Vorsorgeuntersuchung fragen"), String(localized: "Vorhandene Befunde und Medikamentenliste bereitlegen")]
        case .child:
            if answers.last == "family" { return [String(localized: "Familienberatungsstelle auswählen"), String(localized: "Gesprächstermin anfragen")] }
            if answers.last == "movement" { return [String(localized: "Altersgeeignete Bewegungsangebote prüfen"), String(localized: "Zeiten und Teilnahmebedingungen klären")] }
            return [String(localized: "Vorhandene Untersuchungsunterlagen bereitlegen"), String(localized: "Angebote mit der Kinderarztpraxis besprechen")]
        }
    }
    func taskID(_ index: Int) -> UUID {
        if scenario == .hospital, let prep = preparation, let source = prep.sourceDocumentID {
            let key = index == 0 ? "review" : prep.recommendations.filter(\.reviewed).dropFirst(index - 1).first?.kind.rawValue ?? String(index)
            return LifePathSeed.stableID("case-hospital-" + source.uuidString + key)
        }
        return LifePathSeed.stableID("scenario-" + scenario.rawValue + "-" + String(index))
    }
}
