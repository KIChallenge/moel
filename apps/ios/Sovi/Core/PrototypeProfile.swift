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
    var title: String {
        switch self {
        case .firstName: String(localized: "Vorname")
        case .lastName: String(localized: "Nachname")
        case .birthDate: String(localized: "Geburtsdatum (TT.MM.JJJJ)")
        case .street: String(localized: "Straße")
        case .house: String(localized: "Hausnummer")
        case .postcode: String(localized: "Postleitzahl")
        case .city: String(localized: "Ort")
        case .phone: String(localized: "Telefon")
        case .email: String(localized: "E-Mail")
        case .insuranceNumber: String(localized: "Sozialversicherungsnummer")
        case .insurer: String(localized: "Versicherungsträger")
        case .title: String(localized: "Titel")
        case .stair: String(localized: "Stiege")
        case .door: String(localized: "Tür")
        case .country: String(localized: "Land")
        case .nationality: String(localized: "Staatsbürgerschaft")
        case .birthCountry: String(localized: "Geburtsland")
        case .maritalStatus: String(localized: "Familienstand")
        case .iban: "IBAN"
        case .accountHolder: String(localized: "Kontoinhaber:in")
        case .fswNumber: String(localized: "FSW-Kund:innennummer")
        }
    }
    var question: String {
        switch self {
        case .firstName: String(localized: "Hallo, ich bin Sovi. Wie heißt du mit Vornamen?")
        case .lastName: String(localized: "Und dein Nachname? Damit kann ich Formulare für dich vorbereiten.")
        case .birthDate: String(localized: "Wann bist du geboren? Schreib bitte TT.MM.JJJJ. Du kannst auch überspringen.")
        case .street: String(localized: "In welcher Straße wohnst du?")
        case .house: String(localized: "Welche Hausnummer? Stiege und Tür kannst du später ergänzen.")
        case .postcode: String(localized: "Wie lautet deine Postleitzahl?")
        case .city: String(localized: "Und in welchem Ort wohnst du?")
        case .phone: String(localized: "Welche Telefonnummer soll ich in Formularen verwenden?")
        case .email: String(localized: "Welche E-Mail-Adresse möchtest du verwenden?")
        case .insuranceNumber: String(localized: "Möchtest du deine zehnstellige Sozialversicherungsnummer speichern? Du kannst sie auch erst beim Formular ergänzen.")
        case .insurer: String(localized: "Bei welchem Träger bist du versichert?")
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
            guard value.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else { return String(localized: "Bitte die E-Mail-Adresse prüfen.") }
        default: break
        }
        return nil
    }
}

struct WelcomeProgress: Codable, Equatable, Sendable {
    static let fields: [PersonField] = [.firstName, .lastName, .birthDate, .street, .house, .postcode, .city, .phone, .email, .insuranceNumber, .insurer]
    var personID: UUID
    var step = 0
    var completed = false
    var history: [ConversationTurn] = []
    var field: PersonField? { Self.fields.indices.contains(step) ? Self.fields[step] : nil }
    var isLocationStep: Bool { step == Self.fields.count }
    var isNotificationStep: Bool { step == Self.fields.count + 1 }
    var question: String {
        if let field { return field.question }
        if isLocationStep { return String(localized: "Soll ich deinen aktuellen Standort für Angebote in deiner Nähe verwenden? Er wird bei einer Suche neu abgefragt und ersetzt keine Wohnadresse. Apple kann daraus einen Ortsnamen bestimmen. Im Online-Chat geht der Standort an den Sovi-Server, nicht an OpenAI.") }
        return String(localized: "Möchtest du Erinnerungen an deine offenen Schritte und Termine? Die Mitteilungen bleiben kurz und enthalten keine Gesundheitsdetails.")
    }
}
