import Foundation

struct SavedFormDraft: Codable, Equatable, Sendable {
    var formID: String
    var personID: UUID
    var values: [String: String]
    var caseScenario: String?
    var selections: [String: String]?
    var storageKey: String { formID + ":" + personID.uuidString }
}

/// Reusable, explicitly entered form data. Never part of an online-chat payload.
struct FormPerson: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var label = ""
    var isSelf = false
    var values: [String: String] = [:]
    var name: String { [values["firstName"], values["lastName"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
    var displayName: String { name.isEmpty ? (label.isEmpty ? String(localized: "Mein Profil") : label) : name }
    var address: String {
        [([values["street"], values["house"]].compactMap { $0 }.joined(separator: " ")),
         ([values["postcode"], values["city"]].compactMap { $0 }.joined(separator: " "))]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum PersonField: String, CaseIterable, Identifiable {
    case firstName, lastName, birthDate, street, house, postcode, city, phone, email, insuranceNumber, insurer
    case title, stair, door, country, nationality, birthCountry, maritalStatus, iban, accountHolder, fswNumber
    var id: String { rawValue }
    var title: String { title(in: .app) }
    func title(in language: ChatLanguage) -> String {
        switch self {
        case .firstName: language.text("Vorname")
        case .lastName: language.text("Nachname")
        case .birthDate: language.text("Geburtsdatum (TT.MM.JJJJ)")
        case .street: language.text("Straße")
        case .house: language.text("Hausnummer")
        case .postcode: language.text("Postleitzahl")
        case .city: language.text("Ort")
        case .phone: language.text("Telefon")
        case .email: language.text("E-Mail")
        case .insuranceNumber: language.text("Sozialversicherungsnummer")
        case .insurer: language.text("Versicherungsträger")
        case .title: language.text("Titel")
        case .stair: language.text("Stiege")
        case .door: language.text("Tür")
        case .country: language.text("Land")
        case .nationality: language.text("Staatsbürgerschaft")
        case .birthCountry: language.text("Geburtsland")
        case .maritalStatus: language.text("Familienstand")
        case .iban: "IBAN"
        case .accountHolder: language.text("Kontoinhaber:in")
        case .fswNumber: language.text("FSW-Kund:innennummer")
        }
    }
    var question: String {
        switch self {
        case .firstName: String(localized: "Wie heißt du mit Vornamen?")
        case .lastName: String(localized: "Wie ist dein Nachname?")
        case .birthDate: String(localized: "Wann bist du geboren?")
        case .street: String(localized: "Wo wohnst du?")
        case .house: String(localized: "Welche Hausnummer? Stiege und Tür kannst du später ergänzen.")
        case .postcode: String(localized: "Wie lautet deine Postleitzahl?")
        case .city: String(localized: "Und in welchem Ort wohnst du?")
        case .phone: String(localized: "Unter welcher Telefonnummer kann man dich erreichen?")
        case .email: String(localized: "Wie lautet deine E-Mail-Adresse?")
        case .insuranceNumber: String(localized: "Wie lautet deine Sozialversicherungsnummer? Du findest die 10 Ziffern auf deiner e-card.")
        case .insurer: String(localized: "Bei welcher Versicherung bist du?")
        default: title
        }
    }

    func validate(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 200 else { return String(localized: "Bitte kürzer antworten (maximal 200 Zeichen).") }
        guard !value.isEmpty else { return nil }
        switch self {
        case .birthDate:
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "dd.MM.yyyy"; f.isLenient = false
            guard let date = f.date(from: value), f.string(from: date) == value, date <= Date() else { return String(localized: "Bitte ein gültiges Geburtsdatum als TT.MM.JJJJ eingeben.") }
        case .insuranceNumber:
            guard value.range(of: "^[0-9]{10}$", options: .regularExpression) != nil else { return String(localized: "Bitte zehn Ziffern eingeben oder überspringen.") }
        case .email:
            let parts = value.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].hasPrefix("."), !parts[0].hasSuffix("."), !parts[0].contains(".."),
                  value.range(of: "^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$", options: [.regularExpression, .caseInsensitive]) != nil,
                  parts[1].split(separator: ".").allSatisfy({ $0.count <= 63 }) else { return String(localized: "Bitte die E-Mail-Adresse prüfen.") }
        case .phone:
            let digits = value.filter { $0.isASCII && $0.isNumber }
            guard (7...15).contains(digits.count), value.range(of: "^\\+?[0-9][0-9 ()/.-]*$", options: .regularExpression) != nil else {
                return String(localized: "Bitte eine gültige Telefonnummer eingeben, zum Beispiel +43 660 1234567.")
            }
        default: break
        }
        return nil
    }
}

struct WelcomeProgress: Codable, Equatable, Sendable {
    static let fields: [PersonField] = [.firstName, .lastName, .birthDate, .street, .phone, .email, .insuranceNumber, .insurer]
    private static let legacyFields: [PersonField] = [.firstName, .lastName, .birthDate, .street, .house, .postcode, .city, .phone, .email, .insuranceNumber, .insurer]
    static let termsVersion = "2026-11-05"
    var personID: UUID
    var step = -2
    var completed = false
    var history: [ConversationTurn] = []
    // Missing version means a saved conversation from the earlier field sequence.
    var flowVersion: Int? = 2
    var termsAcceptedAt: Date?
    var acceptedTermsVersion: String?
    var termsMessageID: UUID?
    var activeFields: [PersonField] { flowVersion == nil ? Self.legacyFields : Self.fields }
    var field: PersonField? { activeFields.indices.contains(step) ? activeFields[step] : nil }
    var isGreetingStep: Bool { step == -2 }
    var isTermsStep: Bool { step == -1 }
    var isAddressStep: Bool { field == .street }
    var isLocationStep: Bool { step == activeFields.count }
    var isNotificationStep: Bool { step == activeFields.count + 1 }
    var question: String {
        if isGreetingStep { return String(localized: "Hi, ich bin Sovi, dein persönlicher Gesundheitsbegleiter.") }
        if isTermsStep { return String(localized: "Hier findest du die Nutzungsbedingungen. Bitte lies sie kurz durch, bevor wir starten.") }
        if let field { return field.question }
        if isLocationStep { return String(localized: "Darf ich deinen Standort nutzen, um Angebote in deiner Nähe zu finden?") }
        return String(localized: "Darf ich dich an deine Termine und nächsten Schritte erinnern?")
    }

    mutating func recordAnswer(_ value: String?, address: WelcomeAddress? = nil, finish: Bool = false, person: inout FormPerson, now: Date) throws {
        guard !completed else { throw SoviError.invalidAction }
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        var reply = value ?? String(localized: finish ? "Später ergänzen" : "Überspringen")
        if !finish {
            if isGreetingStep {
                guard value == String(localized: "Hi") else { throw SoviError.invalidAction }
            } else if isTermsStep {
                guard value == String(localized: "Akzeptieren") else { throw SoviError.invalidAction }
                termsAcceptedAt = now; acceptedTermsVersion = Self.termsVersion
            } else if isAddressStep, let value, !value.isEmpty {
                let entered = try address ?? WelcomeAddress(manual: value)
                try entered.validate()
                person.values.merge(entered.values) { _, new in new }
                reply = entered.displayText
            } else if let field, let value, !value.isEmpty {
                if let error = field.validate(value) { throw SoviError.invalidInput(error) }
                person.values[field.rawValue] = value
                if field == .birthDate, let date = Self.birthDateFormatter.date(from: value) {
                    reply = date.formatted(date: .long, time: .omitted)
                }
            }
        }
        history.append(ConversationTurn(role: "user", text: reply, date: now))
        let wasAddress = isAddressStep
        step = finish ? activeFields.count + 2 : step + 1
        if wasAddress && !finish { step = activeFields.firstIndex(of: .phone) ?? step }
        completed = step >= activeFields.count + 2
        if isTermsStep {
            history.append(ConversationTurn(role: "assistant", text: String(localized: "Damit ich dir wirklich helfen kann, würde ich dich gern besser kennenlernen."), date: now))
        }
        let message = ConversationTurn(role: "assistant", text: completed ? String(localized: "Danke! Jetzt können wir loslegen. Du kannst deine Angaben jederzeit ändern.") : question, date: now)
        if isTermsStep { termsMessageID = message.id }
        history.append(message)
    }

    static var birthDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.isLenient = false
        return formatter
    }
}

/// A confirmed address is stored in separate fields so existing forms can reuse it.
struct WelcomeAddress: Equatable, Sendable {
    var street: String
    var house: String
    var postcode: String
    var city: String
    var country: String = ""
    var displayText: String { [street + " " + house, postcode + " " + city, country].filter { !$0.isEmpty }.joined(separator: ", ") }
    var values: [String: String] {
        var fields = ["street": street, "house": house, "postcode": postcode, "city": city]
        if !country.isEmpty { fields["country"] = country }
        return fields
    }

    init(street: String, house: String, postcode: String, city: String, country: String = "") {
        self.street = street; self.house = house; self.postcode = postcode; self.city = city; self.country = country
    }

    init(manual: String) throws {
        let parts = manual.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2,
              let streetMatch = parts[0].range(of: "\\s+[0-9]+[A-Za-z0-9/.-]*$", options: .regularExpression),
              let postalMatch = parts[1].range(of: "^[0-9]{4,10}\\s+", options: .regularExpression) else {
            throw SoviError.invalidInput(String(localized: "Bitte Straße und Hausnummer, dann PLZ und Ort eingeben. Oder wähle einen Adressvorschlag."))
        }
        street = String(parts[0][..<streetMatch.lowerBound]).trimmingCharacters(in: .whitespaces)
        house = String(parts[0][streetMatch]).trimmingCharacters(in: .whitespaces)
        postcode = String(parts[1][postalMatch]).trimmingCharacters(in: .whitespaces)
        city = String(parts[1][postalMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
        country = parts.dropFirst(2).joined(separator: ", ")
        try validate()
    }

    func validate() throws {
        guard [street, house, postcode, city].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              values.values.allSatisfy({ $0.count <= 200 }) else {
            throw SoviError.invalidInput(String(localized: "Bitte ergänze Straße, Hausnummer, PLZ und Ort."))
        }
    }
}
