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

enum PersonField: String, CaseIterable, Identifiable, Codable, Sendable {
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

enum ECardSide: String, Codable, Sendable {
    case front, back

    var caption: String {
        switch self {
        case .front: String(localized: "Vorderseite der e-card")
        case .back: String(localized: "Rückseite der e-card")
        }
    }
}

struct WelcomeECardPhoto: Codable, Equatable, Sendable {
    static let maxBytes = 512 * 1024
    let side: ECardSide
    let jpeg: Data
}

struct WelcomeECardScanDraft: Codable, Equatable, Sendable {
    let id: UUID
    var front: [PersonField: String]?
    var back: [PersonField: String]?

    var nextSide: ECardSide? {
        if front == nil { return .front }
        return back == nil ? .back : nil
    }

    var recognized: [PersonField: String] {
        (front ?? [:]).merging(back ?? [:]) { frontValue, _ in frontValue }
    }
}

enum WelcomeECardAction {
    case start
    case post(UUID, WelcomeECardPhoto, [PersonField: String])
    case confirm(UUID, [PersonField: String])
    case cancel(UUID)
}

enum WelcomeReply: String {
    case useLocation = "Ja, verwende meinen Standort"
    case enterPlace = "Nein, ich gebe den Ort selbst ein"
    case remindMe = "Ja, erinnere mich bitte"
    case noReminders = "Nein, danke"
    case confirmCard = "Ja, so stimmt’s"

    var text: String { ChatLanguage.app.text(rawValue) }
}

struct WelcomeProgress: Codable, Equatable, Sendable {
    static let fields: [PersonField] = [.firstName, .lastName, .birthDate, .street, .phone, .email, .insuranceNumber, .insurer]
    static let eCardFields: [PersonField] = [.firstName, .lastName, .birthDate, .insuranceNumber, .insurer]
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
    // Confirmed values live in the profile. This set identifies the questions to skip.
    private(set) var reviewedECardFields: Set<PersonField>?
    private(set) var eCardScan: WelcomeECardScanDraft?
    var activeFields: [PersonField] { flowVersion == nil ? Self.legacyFields : Self.fields }
    var field: PersonField? { activeFields.indices.contains(step) ? activeFields[step] : nil }
    var isGreetingStep: Bool { step == -2 }
    var isTermsStep: Bool { step == -1 }
    var isAddressStep: Bool { field == .street }
    var isLocationStep: Bool { step == activeFields.count }
    var isNotificationStep: Bool { step == activeFields.count + 1 }

    private static let locationQuestion = "Darf ich deinen Standort nutzen, um Angebote in deiner Nähe zu finden?"
    private static let reminderQuestion = "Darf ich dich an deine Termine und nächsten Schritte erinnern?"

    // Earlier builds saved localized status labels as user turns. Match the preceding
    // permission question too, so ordinary typed answers keep their original text.
    private static let legacyPermissionReplies: [String: [String: (role: String, text: String)]] = {
        var result: [String: [String: (role: String, text: String)]] = [:]
        for language in [ChatLanguage.de, .en] {
            let t = language.text
            result[t(locationQuestion)] = [
                t("Standort erlaubt"): ("user", t(WelcomeReply.useLocation.rawValue)),
                t("Ohne Standort weiter"): ("user", t(WelcomeReply.enterPlace.rawValue)),
                t("Standort nicht verfügbar – Ort bei Bedarf eingeben"): ("assistant", t("Ich kann deinen Standort gerade nicht verwenden."))
            ]
            result[t(reminderQuestion)] = [
                t("Erinnerungen erlaubt"): ("user", t(WelcomeReply.remindMe.rawValue)),
                t("Ohne Erinnerungen weiter"): ("user", t("Ich mache ohne Erinnerungen weiter."))
            ]
        }
        return result
    }()

    var displayHistory: [ConversationTurn] {
        var turns = history
        for index in history.indices.dropFirst() where history[index].role == "user" {
            let previous = history[index - 1]
            if previous.role == "assistant", let reply = Self.legacyPermissionReplies[previous.text]?[history[index].text] {
                turns[index].role = reply.role
                turns[index].text = reply.text
            }
        }
        return turns
    }

    func remainingECardFields(for person: FormPerson) -> [PersonField] {
        guard !completed, field != nil, person.id == personID, person.isSelf,
              termsAcceptedAt != nil, acceptedTermsVersion == Self.termsVersion else { return [] }
        return activeFields[step...].filter { field in
            Self.eCardFields.contains(field) && (person.values[field.rawValue] ?? "").isEmpty
        }
    }

    mutating func handleECard(_ action: WelcomeECardAction, person: inout FormPerson, now: Date) throws {
        switch action {
        case .start:
            guard eCardScan == nil, let field, remainingECardFields(for: person).contains(field) else { throw SoviError.invalidAction }
            let prompt = ConversationTurn(role: "assistant", text: String(localized: "Zeig mir zuerst die Vorderseite deiner e-card."), date: now)
            eCardScan = WelcomeECardScanDraft(id: prompt.id)
            history.append(prompt)
        case .post(let id, let photo, let fields):
            guard var draft = eCardScan, draft.id == id, draft.nextSide == photo.side,
                  !remainingECardFields(for: person).isEmpty, fields.keys.allSatisfy(Self.eCardFields.contains),
                  photo.jpeg.starts(with: [0xFF, 0xD8]), photo.jpeg.count <= WelcomeECardPhoto.maxBytes else { throw SoviError.invalidAction }
            let identity: [PersonField] = [.firstName, .lastName, .birthDate, .insuranceNumber]
            if identity.contains(where: { Self.agrees(fields[$0], person.values[$0.rawValue]) == false }) {
                throw SoviError.invalidInput(String(localized: "Die Angaben auf der Karte passen nicht zu deinen bisherigen Antworten."))
            }
            if photo.side == .front {
                guard !fields.isEmpty else { throw SoviError.invalidAction }
                draft.front = fields
            } else {
                guard let front = draft.front else { throw SoviError.invalidAction }
                if !fields.isEmpty {
                    let sameNumber = Self.agrees(fields[.insuranceNumber], front[.insuranceNumber]) == true
                    let sameName = Self.agrees(fields[.firstName], front[.firstName]) == true && Self.agrees(fields[.lastName], front[.lastName]) == true
                    guard (sameNumber || sameName), !identity.contains(where: { Self.agrees(fields[$0], front[$0]) == false }) else {
                        throw SoviError.invalidInput(String(localized: "Ich kann die Seiten nicht derselben Karte zuordnen. Bitte fotografiere die Rückseite noch einmal."))
                    }
                }
                draft.back = fields
            }
            history.append(ConversationTurn(role: "user", text: photo.side.caption, date: now, eCardPhoto: photo))
            eCardScan = draft
            let reply: String
            if photo.side == .front {
                reply = String(localized: "Jetzt die Rückseite, bitte.")
            } else if remainingECardFields(for: person).contains(where: { draft.recognized[$0] != nil }) {
                reply = String(localized: "Stimmen die Angaben?")
            } else {
                eCardScan = nil
                reply = String(localized: "Für die offenen Fragen konnte ich keine Angaben lesen.") + " " + question
            }
            history.append(ConversationTurn(role: "assistant", text: reply, date: now))
        case .confirm(let id, let values):
            guard let scan = eCardScan, scan.id == id, scan.nextSide == nil else { throw SoviError.invalidAction }
            try confirmECard(values, from: scan, person: &person, now: now)
        case .cancel(let id):
            guard eCardScan?.id == id else { throw SoviError.invalidAction }
            discardECardDraft()
        }
    }

    /// Missing values neither identify a cardholder nor contradict another side.
    private static func agrees(_ lhs: String?, _ rhs: String?) -> Bool? {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return nil }
        return lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT")) == .orderedSame
    }

    private mutating func discardECardDraft() {
        if let start = history.firstIndex(where: { $0.id == eCardScan?.id }) { history.removeSubrange(start...) }
        eCardScan = nil
    }

    private mutating func confirmECard(_ values: [PersonField: String], from scan: WelcomeECardScanDraft, person: inout FormPerson, now: Date) throws {
        guard values.keys.allSatisfy(Self.eCardFields.contains) else { throw SoviError.invalidAction }
        let available = remainingECardFields(for: person)
        var accepted: [PersonField: String] = [:]
        for field in available {
            guard let value = values[field]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
            guard scan.recognized[field] != nil else { throw SoviError.invalidAction }
            if let error = field.validate(value) { throw SoviError.invalidInput(error) }
            accepted[field] = value
        }
        guard !accepted.isEmpty else { throw SoviError.invalidAction }
        for (field, value) in accepted { person.values[field.rawValue] = value }
        reviewedECardFields = (reviewedECardFields ?? []).union(accepted.keys)
        eCardScan = nil
        history.append(ConversationTurn(role: "user", text: WelcomeReply.confirmCard.text, date: now))
        skipReviewedECardFields(in: person)
        history.append(ConversationTurn(role: "assistant", text: question, date: now))
    }

    private mutating func skipReviewedECardFields(in person: FormPerson) {
        while let field, reviewedECardFields?.contains(field) == true, !(person.values[field.rawValue] ?? "").isEmpty {
            step += 1
        }
    }

    var question: String {
        if isGreetingStep { return String(localized: "Hi, ich bin Sovi, dein persönlicher Gesundheitsbegleiter.") }
        if isTermsStep { return String(localized: "Hier findest du die Nutzungsbedingungen. Bitte lies sie kurz durch, bevor wir starten.") }
        if let field { return field.question }
        return ChatLanguage.app.text(isLocationStep ? Self.locationQuestion : Self.reminderQuestion)
    }

    mutating func recordAnswer(_ value: String?, address: WelcomeAddress? = nil, finish: Bool = false, permissionUnavailable: Bool = false, person: inout FormPerson, now: Date) throws {
        guard !completed, eCardScan == nil || finish else { throw SoviError.invalidAction }
        if permissionUnavailable {
            let expected = isLocationStep ? WelcomeReply.useLocation : .remindMe
            guard !finish, isLocationStep || isNotificationStep, value == expected.text else { throw SoviError.invalidAction }
        }
        // Leaving onboarding keeps posted messages. Only the explicit discard action removes photos.
        if finish { eCardScan = nil }
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        var reply = value ?? String(localized: finish ? "Den Rest ergänze ich später." : "Das lasse ich erst mal offen.")
        if !finish {
            if isGreetingStep {
                guard value == String(localized: "Hi") else { throw SoviError.invalidAction }
            } else if isTermsStep {
                guard value == String(localized: "Akzeptieren") else { throw SoviError.invalidAction }
                termsAcceptedAt = now; acceptedTermsVersion = Self.termsVersion
                reply = String(localized: "Ich stimme zu.")
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
                } else if field == .insuranceNumber {
                    reply = String(localized: "Ich habe meine Versicherungsnummer eingetragen.")
                }
            }
        }
        history.append(ConversationTurn(role: "user", text: reply, date: now))
        if permissionUnavailable {
            let notice = isLocationStep ? String(localized: "Ich kann deinen Standort gerade nicht verwenden.")
                : String(localized: "Ich kann dir gerade keine Erinnerungen schicken.")
            history.append(ConversationTurn(role: "assistant", text: notice, date: now))
        }
        let wasAddress = isAddressStep
        step = finish ? activeFields.count + 2 : step + 1
        if wasAddress && !finish { step = activeFields.firstIndex(of: .phone) ?? step }
        skipReviewedECardFields(in: person)
        completed = step >= activeFields.count + 2
        if isTermsStep {
            history.append(ConversationTurn(role: "assistant", text: String(localized: "Damit ich dir wirklich helfen kann, würde ich dich gern besser kennenlernen."), date: now))
        }
        let message = ConversationTurn(role: "assistant", text: completed ? String(localized: "Danke! Jetzt können wir loslegen.") : question, date: now)
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
