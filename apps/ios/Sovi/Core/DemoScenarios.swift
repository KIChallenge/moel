import Foundation
import NaturalLanguage

enum ChatLanguage: String, Codable, Sendable {
    case de, en, ar, tr

    static var app: Self {
        Bundle.main.preferredLocalizations.first.flatMap { Self(rawValue: String($0.prefix(2))) } ?? .de
    }

    static func resolve(_ message: String, preference: String = "auto") -> Self {
        if let explicit = Self(rawValue: preference) { return explicit }
        guard !message.isEmpty else { return app }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english, .arabic, .turkish]
        recognizer.processString(message)
        return recognizer.dominantLanguage.flatMap { Self(rawValue: $0.rawValue) } ?? app
    }

    /// Use the requested conversation language regardless of the device UI language.
    func text(_ key: String) -> String {
        guard self != .de else { return key }
        for code in [rawValue, "en"] {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                let result = bundle.localizedString(forKey: key, value: key, table: nil)
                if result != key { return result }
            }
        }
        return key
    }

    func localized(_ value: String.LocalizationValue) -> String {
        let bundle = Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
        return String(localized: value, bundle: bundle, locale: Locale(identifier: rawValue))
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_AT"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
    }
}

enum DemoScenario: String, Codable, CaseIterable, Identifiable, Sendable {
    case care, hospital, health, child
    var id: String { rawValue }
    var title: String { title(in: .app) }
    func title(in language: ChatLanguage) -> String {
        switch self {
        case .care: language.text("Hilfe für meine Mutter")
        case .hospital: language.text("Nach dem Spital")
        case .health: language.text("Etwas für meine Gesundheit tun")
        case .child: language.text("Angebote für mein Kind")
        }
    }
    static func matching(_ text: String) -> Self? {
        let t = ChatLanguage.normalized(text)
        func has(_ words: [String]) -> Bool { words.contains { t.contains(ChatLanguage.normalized($0)) } }
        if has(["pflegegeld", "pflegeberatung", "mobile pflege", "care allowance", "care benefit", "bakim parasi", "bakim yardim", "بدل الرعاية"]) ||
            has(["mutter", "mother", "mum", "mom", "annem", "والدتي", "امي"]) &&
            has(["hilfe", "help", "allein", "alone", "pflege", "support", "care", "manage", "zurecht", "yardim", "bakim", "yalniz", "مساعدة", "رعاية", "وحدها"]) { return .care }
        if has(["nach dem spital", "nach dem krankenhaus", "after hospital", "after my hospital", "discharged", "discharge letter", "discharge report", "entlassungsbrief", "entlassungsbefund", "taburcu", "hastaneden", "تقرير الخروج", "خروجي من المستشفى"]) { return .hospital }
        if has(["kind", "child", "son ", "daughter", "cocug", "cocuk", "طفل", "ابنتي", "ابني"]) &&
            has(["angebot", "vorsorge", "beratung", "unterstutz", "available", "offers", "support", "program", "services", "destek", "hizmet", "olanak", "خدمات", "عروض", "دعم"]) { return .child }
        if has(["meine gesundheit", "healthier", "my health", "health promotion", "gesundheitsforderung", "bewegt im park", "vorsorgeuntersuchung", "sagligim", "saglikli", "صحتي", "تحسين الصحة"]) { return .health }
        return nil
    }
}

struct DemoScenarioProgress: Codable, Equatable, Sendable {
    var scenario: DemoScenario
    var language: ChatLanguage?
    var replyLanguage: ChatLanguage { language ?? .app }
    var answers: [String] = []
    var history: [ConversationTurn] = []
    var saved = false
    var preparation: CasePreparation?
    var finished: Bool { answers.count >= (scenario == .health ? 1 : 2) }
    var question: String {
        switch scenario {
        case .care: answers.isEmpty ? replyLanguage.text("Was braucht deine Mutter gerade: Hilfe zu Hause, finanzielle Unterstützung oder beides?") : replyLanguage.text("In welchem Ort lebt deine Mutter? Dein Standort muss nicht ihr Wohnort sein.")
        case .hospital: answers.isEmpty ? replyLanguage.text("Was wurde im Entlassungsbrief empfohlen? Du kannst einen Satz abschreiben oder einen Brief öffnen.") : replyLanguage.text("Wann hättest du am liebsten einen Termin? Das ist ein Wunsch, noch keine Buchung.")
        case .health: replyLanguage.text("Welches Gesundheitsangebot interessiert dich?")
        case .child: answers.isEmpty ? replyLanguage.text("Wie alt ist dein Kind? Es reicht eine Zahl in Jahren.") : replyLanguage.text("Welche Angebote suchst du für dein Kind?")
        }
    }
    var choices: [String] {
        guard !finished else { return [] }
        return switch scenario {
        case .care: answers.isEmpty ? [replyLanguage.text("Hilfe zu Hause"), replyLanguage.text("Pflegegeld vorbereiten"), replyLanguage.text("Beides")] : ["Wien", "Graz", "Linz"]
        case .hospital: answers.isEmpty ? [replyLanguage.text("Hinterlegten Brief öffnen")] : [replyLanguage.text("Vormittags"), replyLanguage.text("Nachmittags"), replyLanguage.text("Zeitlich flexibel")]
        case .health: [replyLanguage.text("Vorsorge"), replyLanguage.text("Bewegung"), replyLanguage.text("Ernährung"), replyLanguage.text("Impfangebote"), replyLanguage.text("Gesundheitskurse")]
        case .child: answers.isEmpty ? ["2", "8", "14"] : [replyLanguage.text("Vorsorge"), replyLanguage.text("Familienberatung"), replyLanguage.text("Bewegung"), replyLanguage.text("Impfangebote"), replyLanguage.text("Ernährung"), replyLanguage.text("Familienleistungen")]
        }
    }
    static var sampleLetter: String { String(localized: "Eine ambulante Rehabilitation wird empfohlen. Eine ärztliche Nachkontrolle soll vereinbart werden.") }
    func normalizedAnswer(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 600 else { throw SoviError.invalidInput(replyLanguage.text("Bitte kurz antworten (maximal 600 Zeichen).")) }
        if scenario == .hospital && answers.isEmpty {
            if text == replyLanguage.text("Hinterlegten Brief öffnen") { return Self.sampleLetter }
            let lower = text.lowercased()
            guard (lower.contains("empfohl") || lower.contains("recommended") || lower.contains("vereinbar")),
                  (lower.contains("rehab") || lower.contains("kontroll") || lower.contains("follow-up")) else {
                throw SoviError.invalidInput(replyLanguage.text("Bitte übernimm die Empfehlung zu Reha oder Nachkontrolle aus deinem Brief. Du kannst auch einen Brief öffnen."))
            }
        }
        if scenario == .child && answers.isEmpty {
            let numbers = text.split(whereSeparator: { !$0.isNumber })
            guard text.range(of: #"-\s*\d"#, options: .regularExpression) == nil, numbers.count == 1, let age = Int(numbers[0].compactMap(\.wholeNumberValue).map(String.init).joined()), (0...17).contains(age) else { throw SoviError.invalidInput(replyLanguage.text("Bitte das Alter als Zahl von 0 bis 17 eingeben.")) }
            return String(age)
        }
        if answers.isEmpty && [.care, .health].contains(scenario) || scenario == .child && answers.count == 1 {
            if let choice = recognizedChoice(text) { return choice }
            guard choices.contains(text) else { throw SoviError.invalidInput(replyLanguage.text("Bitte wähle eine der Möglichkeiten. Andere Anliegen kannst du im Chat stellen.")) }
        }
        if let index = choices.firstIndex(of: text) {
            if scenario == .care && answers.isEmpty { return ["home", "money", "both"][index] }
            if scenario == .health { return ["prevention", "movement", "nutrition", "vaccinations", "courses"][index] }
            if scenario == .child && answers.count == 1 { return ["prevention", "family", "movement", "vaccinations", "nutrition", "benefits"][index] }
        }
        return text
    }
    /// Return a stable choice only when the message unambiguously selects a branch.
    func recognizedChoice(_ answer: String) -> String? {
        let t = ChatLanguage.normalized(answer)
        let options: [(String, [String])]
        let vaccinations = ("vaccinations", ["impf", "vaccin", "asi", "لقاح", "تطعيم"])
        let nutrition = ("nutrition", ["ernahrung", "nutrition", "diet", "beslenme", "تغذ"])
        switch scenario {
        case .care:
            if ["both", "beides", "ikisi", "her ikisi", "الاثنين", "كلاهما"].contains(where: t.contains) { return "both" }
            options = [("home", ["zu hause", "daheim", "home help", "at home", "home care", "evde", "في المنزل"]),
                       ("money", ["pflegegeld", "care allowance", "financial", "bakim parasi", "مالي", "بدل الرعاية"])]
        case .health:
            options = [("movement", ["bewegung", "sport", "exercise", "activity", "movement", "egzersiz", "hareket", "رياض", "حركة"]),
                       nutrition, vaccinations, ("courses", ["gesundheitskurs", "health class", "health course", "saglik kurs", "دورات صح"]),
                       ("prevention", ["vorsorge", "checkup", "check-up", "check up", "prevention", "tarama", "kontrol", "وقاية", "فحص"])]
        case .child:
            options = [nutrition, vaccinations, ("benefits", ["familienleistung", "familienbeihilfe", "family benefit", "family allowance", "aile yardim", "اعانة", "إعانة", "المزايا"]), ("family", ["familienberat", "family counsel", "family advice", "aile danis", "استشار"]),
                       ("movement", ["bewegung", "sport", "exercise", "activity", "movement", "hareket", "رياض", "حركة"]),
                       ("prevention", ["vorsorge", "prevent", "check-up", "kontrol", "وقاية", "فحص"])]
        case .hospital: return nil
        }
        let hits = options.filter { option in
            option.1.contains { phrase in
                if phrase == "asi" { return t.range(of: #"(?<![\p{L}])asi"#, options: .regularExpression) != nil }
                return t.contains(ChatLanguage.normalized(phrase))
            }
        }
        if hits.count == 2 && scenario == .care { return "both" }
        return hits.count == 1 ? hits[0].0 : nil
    }

    var careInVienna: Bool {
        guard scenario == .care, let answer = answers.dropFirst().first else { return false }
        let location = ChatLanguage.normalized(answer).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let cities = ["wien", "vienna", "viyana", "فيينا"]
        return cities.contains(location) || ["lebt in ", "sie lebt in ", "meine mutter lebt in ", "wohnt in ", "sie wohnt in ", "she lives in ", "my mother lives in ", "تعيش في "].contains { prefix in
            cities.contains(where: { location == prefix + $0 })
        }
    }

    var suggestedForm: String? {
        preparation?.formIDs(for: self).first
    }
    var sources: [(String, String)] {
        if [.health, .child].contains(scenario) {
            switch answers.last {
            case "vaccinations": return [(replyLanguage.text("Impfangebote"), "https://www.gesundheit.gv.at/gesundheitsleistungen/elga/elektronischer-impfpass.html")]
            case "nutrition": return [(replyLanguage.text("Ernährung"), "https://www.gesundheit.gv.at/leben/ernaehrung.html")]
            case "benefits": return [(replyLanguage.text("Familienleistungen"), "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familienbeihilfe")]
            case "courses": return [(replyLanguage.text("Gesundheitskurse"), "https://www.bewegt-im-park.at/")]
            default: break
            }
        }
        switch scenario {
        case .care:
            if careInVienna { return [("Fonds Soziales Wien", "https://www.fsw.at/p/pflege-betreuung"), (replyLanguage.text("Pflegegeld und Antrag"), "https://www.pv.at/web/pflegegeld")] }
            return [(replyLanguage.text("Pflegeberatung"), "https://pflege.gv.at/de/beratungsstellen-im-bundesland"), (replyLanguage.text("Pflegegeld und Antrag"), "https://www.pv.at/web/pflegegeld")]
        case .hospital: return [(replyLanguage.text("Rehabilitation organisieren"), "https://www.gesundheit.gv.at/gesundheitsleistungen/kur-reha/medizinische-rehabilitation.html"), (replyLanguage.text("Einrichtungen suchen"), "https://rehakompass.goeg.at/")]
        case .health:
            if answers.first == "movement" { return [("Bewegt im Park", "https://www.bewegt-im-park.at/")] }
            return [(replyLanguage.text("Vorsorgeuntersuchung"), "https://www.gesundheit.gv.at/leben/gesundheitsvorsorge/vorsorgeuntersuchung.html")]
        case .child:
            if answers.last == "family" { return [(replyLanguage.text("Beratungsstellen finden"), "https://www.familienberatung.gv.at/beratungsstellen.html")] }
            if answers.last == "movement" { return [("Bewegt im Park", "https://www.bewegt-im-park.at/")] }
            if let age = answers.first.flatMap(Int.init), age >= 6 { return [(replyLanguage.text("Gesundheitsportal"), "https://www.gesundheit.gv.at/")] }
            return [(replyLanguage.text("Kindesuntersuchungen"), "https://www.gesundheit.gv.at/leben/eltern/eltern-kind-pass/kindesuntersuchungen.html")]
        }
    }
    var summary: String {
        switch scenario {
        case .care: replyLanguage.text("Wir können Beratung und einen passenden Antragsentwurf vorbereiten. Ein Anspruch oder eine Pflegestufe wird hier nicht festgestellt.")
        case .hospital: replyLanguage.text("Wir organisieren nur die ausdrücklich genannte Empfehlung. Die ärztlichen Teile des Reha-Antrags bleiben offen.")
        case .health: replyLanguage.text("Hier ist dein nächster organisatorischer Schritt. Passende medizinische Vorsorge besprichst du mit deiner Praxis. Bewegungskurse sind saisonal; aktuelle Termine bitte auf der Angebotsseite prüfen.")
        case .child: replyLanguage.text("Wir sammeln Angebote und bereiten deine Fragen vor. Es wird kein Untersuchungs- oder Impfbedarf aus dem Alter abgeleitet.")
        }
    }
    var steps: [String] {
        if [.health, .child].contains(scenario) {
            switch answers.last {
            case "vaccinations": return ["Impfpass bereitlegen", "Fragen für die Impfberatung sammeln"].map(replyLanguage.text)
            case "nutrition": return ["Ernährungsangebote ansehen", "Fragen für eine Ernährungsberatung sammeln"].map(replyLanguage.text)
            case "benefits": return ["Informationen zur Familienbeihilfe ansehen", "Benötigte Unterlagen mit der zuständigen Stelle klären"].map(replyLanguage.text)
            case "courses": return ["Aktuelle Bewegungskurse am gewünschten Ort prüfen", "Zeiten und Teilnahmebedingungen klären"].map(replyLanguage.text)
            default: break
            }
        }
        switch scenario {
        case .care:
            if answers.first == "home" { return [replyLanguage.text("Regionale Pflegeberatung kontaktieren"), replyLanguage.text("Mobile Hilfe und benötigte Unterlagen besprechen")] }
            if answers.first == "money" { return [replyLanguage.text("Zuständige Stelle für Pflegegeld klären"), replyLanguage.text("Vorhandene Unterlagen sammeln"), replyLanguage.text("Pflegegeld-Entwurf prüfen") ] }
            return [replyLanguage.text("Regionale Pflegeberatung kontaktieren"), replyLanguage.text("Mobile Hilfe und benötigte Unterlagen besprechen"), replyLanguage.text("Pflegegeld-Entwurf prüfen")]
        case .hospital:
            if let preparation, preparation.sourceDocumentID != nil {
                return [replyLanguage.text("Empfehlung im Entlassungsbrief prüfen")] + preparation.recommendations.filter(\.reviewed).map { $0.title(in: replyLanguage) }
            }
            let text = answers.first?.lowercased() ?? ""
            var list = [replyLanguage.text("Empfehlung im Entlassungsbrief prüfen")]
            if text.contains("rehab") { list += [replyLanguage.text("Reha-Antrag mit behandelnder Praxis vorbereiten")] }
            if text.contains("kontroll") || text.contains("follow-up") { list += [replyLanguage.text("Nachkontrolltermin anfragen")] }
            return list
        case .health:
            if answers.first == "movement" { return [replyLanguage.text("Aktuelle Bewegungskurse am gewünschten Ort prüfen"), replyLanguage.text("Kurs auswählen und Termin selbst bestätigen")] }
            return [replyLanguage.text("Praxis nach Vorsorgeuntersuchung fragen"), replyLanguage.text("Vorhandene Befunde und Medikamentenliste bereitlegen")]
        case .child:
            if answers.last == "family" { return [replyLanguage.text("Familienberatungsstelle auswählen"), replyLanguage.text("Gesprächstermin anfragen")] }
            if answers.last == "movement" { return [replyLanguage.text("Altersgeeignete Bewegungsangebote prüfen"), replyLanguage.text("Zeiten und Teilnahmebedingungen klären")] }
            return [replyLanguage.text("Vorhandene Untersuchungsunterlagen bereitlegen"), replyLanguage.text("Angebote mit der Kinderarztpraxis besprechen")]
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
