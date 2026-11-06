import Foundation

enum NodeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case event, task, information, appointment, medication
    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .event: String(localized: "Ereignis")
        case .task: String(localized: "Aufgabe")
        case .information: String(localized: "Information")
        case .appointment: String(localized: "Termin")
        case .medication: String(localized: "Medikamentenplan")
        }
    }
    var symbol: String {
        switch self {
        case .event: "leaf.fill"
        case .task: "checklist"
        case .information: "info.circle.fill"
        case .appointment: "calendar"
        case .medication: "pills.fill"
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case open, inProgress, waiting, completed, notDone, cancelled
    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .open: String(localized: "Offen")
        case .inProgress: String(localized: "In Arbeit")
        case .waiting: String(localized: "Wartet")
        case .completed: String(localized: "Erledigt")
        case .notDone: String(localized: "Nicht erledigt")
        case .cancelled: String(localized: "Abgebrochen")
        }
    }
    var symbol: String {
        switch self {
        case .open: "circle"
        case .inProgress: "arrow.trianglehead.2.clockwise"
        case .waiting: "clock"
        case .completed: "checkmark"
        case .notDone: "xmark"
        case .cancelled: "xmark"
        }
    }
}

enum AppointmentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case requestDraft, confirmed, cancelled
    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .requestDraft: String(localized: "Anfrageentwurf")
        case .confirmed: String(localized: "Bestätigt")
        case .cancelled: String(localized: "Abgesagt")
        }
    }
}

enum Attendance: String, Codable, CaseIterable, Identifiable, Sendable {
    case unrecorded, attended, notAttended
    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .unrecorded: String(localized: "Teilnahme nicht erfasst")
        case .attended: String(localized: "Teilgenommen")
        case .notAttended: String(localized: "Nicht teilgenommen")
        }
    }
}

enum MedicationLog: String, Codable, CaseIterable, Identifiable, Sendable {
    case unrecorded, taken, notTaken
    var id: String { rawValue }
    var displayTitle: String {
        switch self {
        case .unrecorded: String(localized: "Nicht erfasst")
        case .taken: String(localized: "Eingenommen")
        case .notTaken: String(localized: "Nicht eingenommen")
        }
    }
}

enum ProposalKind: String, Codable, Sendable {
    case task, medication, appointment, clarification
    var displayTitle: String {
        switch self {
        case .task: String(localized: "Aufgabe")
        case .medication: String(localized: "Medikamentenplan")
        case .appointment: String(localized: "Terminentwurf")
        case .clarification: String(localized: "Angaben fehlen")
        }
    }
}

enum ProposalStatus: String, Codable, Sendable {
    case pending, approved, rejected
    var displayTitle: String {
        switch self {
        case .pending: String(localized: "Noch zu prüfen")
        case .approved: String(localized: "Übernommen")
        case .rejected: String(localized: "Verworfen")
        }
    }
}

struct EvidenceReference: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var documentID: UUID
    var documentTitle: String
    var locator: String
    var quote: String
    var pageNumber: Int?
}

struct PathNode: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: NodeKind
    var title: String
    var detail: String = ""
    var chapter: Int = 3
    var taskStatus: TaskStatus = .open
    var informationRead = false
    var appointmentID: UUID?
    var scheduleID: UUID?
    var evidence: [EvidenceReference] = []
    var createdAt = Date()
    var date: Date?
    var proposalID: UUID?
    var history: LifeRecord?
    var vaccination: VaccinationRecord?
}

struct DocumentPageSpan: Codable, Equatable, Sendable {
    var pageNumber: Int
    var utf16Start: Int
    var utf16Length: Int
    var usedTextRecognition: Bool?
}

struct SourceDocument: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var text: String
    var importedAt = Date()
    var proposals: [PlanProposal] = []
    var originalFingerprint: String = ""
    var fixtureID: String?
    var bundledPDFName: String?
    var importedPDFData: Data?
    var pageSpans: [DocumentPageSpan]?
}

struct PlanProposal: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var revision = 1
    var title: String
    var detail: String
    var kind: ProposalKind
    var evidence: [EvidenceReference] = []
    var status: ProposalStatus = .pending
    var medicationInstruction: String?
    var medicationStart: Date?
    var medicationEnd: Date?
    var approvedNodeID: UUID?
    var reviewedAt: Date?
}

struct MedicationCorrection: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var previous: MedicationLog
    var value: MedicationLog
    var date: Date
}

struct MedicationOccurrence: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var amount: String
    var log: MedicationLog = .unrecorded
    var corrections: [MedicationCorrection] = []
}

struct MedicationSchedule: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var instruction: String
    var evidence: [EvidenceReference] = []
    var occurrences: [MedicationOccurrence] = []
    var timeZoneIdentifier: String = "Europe/Vienna"
}

struct AppointmentRecord: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var date: Date
    var location: String = ""
    var status: AppointmentStatus = .requestDraft
    var attendance: Attendance = .unrecorded
    var checkInDeferredUntil: Date?
    var provenance: String = "Von dir erfasst."
    var preparation: String = ""
    var createdAt = Date()
    var updatedAt = Date()
}

struct AdministrativeDraft: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var updatedAt: Date
}

struct ConversationTurn: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var role: String
    var text: String
    var date: Date
    var attendanceQuestionID: UUID?
    var attendanceAnswerID: UUID?
    var attachmentDocumentID: UUID?
    var attachmentEventIDs: [UUID]?
    var replyDocumentID: UUID?
}

struct AppState: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var lifeScenario: LifeScenario?
    var lifeDrafts: [String: String]?
    var seededAt: Date?
    var nodes: [PathNode] = []
    var documents: [SourceDocument] = []
    var schedules: [MedicationSchedule] = []
    var appointments: [AppointmentRecord] = []
    var draft: AdministrativeDraft?
    var conversation: [ConversationTurn] = []
    var composerDraft: String = ""
    var notificationsEnabled = false
    var spokenReplies = false
    var straightPath = false
    var fixtureEpoch = Date()
    var fixtureTimeZoneIdentifier: String = "Europe/Vienna"
    var processedOperationIDs: Set<UUID> = []
    var focusContextID: UUID?
    var discussedDocumentID: UUID?
    var vaccinationPassVersion: Int?
    var formPeople: [FormPerson]?
    var welcome: WelcomeProgress?
    var formDrafts: [String: SavedFormDraft]?
    var demoScenarios: [String: DemoScenarioProgress]?
}

enum AppCommand {
    case linkCareReport(UUID, ChatLanguage)
    case leaveDocumentDiscussion
    case discussDocument(documentID: UUID?, question: String?, reply: String, eventIDs: [UUID]? = nil)
    case adoptBefundActions(documentID: UUID, selectedIDs: Set<UUID>, language: String)
    case importVaccinations(documentID: UUID, selectedIDs: Set<UUID>)
    case useCaseDocument(UUID)
    case reviewCaseRecommendation(UUID, Bool)
    case answerCaseQuestion(String, String)
    case restartCaseQuestions
    case setCaseDocument(DemoScenario, String, Bool)
    case setCaseApplicant(DemoScenario, UUID)
    case startScenario(DemoScenario, language: ChatLanguage? = nil, opening: String? = nil)
    case answerScenario(DemoScenario, String)
    case saveScenarioSteps(DemoScenario)
    case startWelcome
    case answerWelcome(String?, finish: Bool = false)
    case answerWelcomeAddress(WelcomeAddress)
    case confirmWelcomeECard([PersonField: String])
    case savePerson(FormPerson)
    case saveFormDraft(String, SavedFormDraft)
    case setTask(UUID, TaskStatus)
    case markRead(UUID, Bool)
    case approveProposal(documentID: UUID, proposalID: UUID, revision: Int, editedTitle: String?)
    case rejectProposal(documentID: UUID, proposalID: UUID, revision: Int)
    case addNode(kind: NodeKind, title: String, detail: String, date: Date?, location: String, appointmentStatus: AppointmentStatus, operationID: UUID = UUID())
    case editAppointment(AppointmentRecord)
    case recordAttendance(UUID, Attendance)
    case beginAttendanceCheckIn(nodeID: UUID, question: String, userMessage: String? = nil)
    case answerAttendanceCheckIn(nodeID: UUID, attendance: Attendance?, answer: String, confirmation: String)
    case recordMedication(scheduleID: UUID, occurrenceID: UUID, log: MedicationLog)
    case saveDraft(String)
    case saveLifeDraft(LifeDraftKind, String)
    case appendConversation(role: String, text: String)
    case saveComposer(String)
    case setFocusContext(UUID?)
    case setPreferences(notifications: Bool?, spokenReplies: Bool?, straightPath: Bool?)
    case deleteLocalData
    case reloadDemo
}

enum SoviError: LocalizedError {
    case missingRecord, invalidAction, staleProposal, incompleteInstruction, unsupportedSchema, invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .missingRecord: String(localized: "Eintrag nicht gefunden.")
        case .invalidAction: String(localized: "Änderung nicht möglich.")
        case .staleProposal: String(localized: "Vorschlag geändert. Bitte erneut prüfen.")
        case .incompleteInstruction: String(localized: "Die vollständige Anweisung fehlt.")
        case .unsupportedSchema: String(localized: "Diese Datenversion wird nicht unterstützt.")
        case .invalidInput(let reason): reason
        }
    }
}

// Presentation copy is separate from saved records and original evidence.

extension ConversationTurn {
    var displayText: String {
        switch text {
        case "Was wurde im Entlassungsbrief ausdrücklich empfohlen? Du kannst einen Satz abschreiben oder den fiktiven Beispielbrief verwenden.",
             "What was explicitly recommended in the discharge letter? Copy a sentence or use the fictional sample letter.":
            return String(localized: "Was wurde im Entlassungsbrief empfohlen? Du kannst einen Satz abschreiben oder einen Brief öffnen.")
        case "Fiktiver Beispielbrief: Eine ambulante Rehabilitation wird empfohlen. Eine ärztliche Nachkontrolle soll vereinbart werden.",
             "Fictional sample letter: Outpatient rehabilitation is recommended. A medical follow-up appointment should be arranged.":
            return String(localized: "Eine ambulante Rehabilitation wird empfohlen. Eine ärztliche Nachkontrolle soll vereinbart werden.")
        case "Für diese Demo brauche ich eine ausdrückliche Empfehlung zu Rehabilitation oder Nachkontrolle. Oder verwende den fiktiven Beispielbrief.",
             "For this demo, use an explicit recommendation for rehabilitation or follow-up, or choose the fictional sample letter.":
            return String(localized: "Bitte übernimm die Empfehlung zu Reha oder Nachkontrolle aus deinem Brief. Du kannst auch einen Brief öffnen.")
        case "Wähle für diese Demo eine der Möglichkeiten. Andere Anliegen kannst du im normalen Chat stellen.",
             "Choose one of the options for this demo. Use the main chat for other requests.":
            return String(localized: "Bitte wähle eine der Möglichkeiten. Andere Anliegen kannst du im Chat stellen.")
        case "Dokument ausgewählt: demo-discharge-navigation.pdf", "Document selected: demo-discharge-navigation.pdf":
            return String(localized: "Dokument ausgewählt: \(String(localized: "Entlassungsbrief"))")
        default: return text
        }
    }
}

extension SourceDocument {
    var displayTitle: String {
        switch fixtureID?.uppercased() {
        case "A": String(localized: "Entlassungsbrief")
        case "B": String(localized: "Medikationsangaben")
        case "C": String(localized: "Weitere Unterlage")
        default: RecordPresentation.sourceTitle(title, id: id)
        }
    }
}

extension EvidenceReference {
    var displayDocumentTitle: String { RecordPresentation.sourceTitle(documentTitle, id: documentID) }
}

extension LifeRecord {
    var displayStatus: String {
        switch sourceStatus {
        case "Demo-dokumentiert", "Verabreichung im Demo dokumentiert": String(localized: "Dokumentiert")
        case "Demo-Eigeneintrag": String(localized: "Selbst eingetragen")
        case "Demo-erledigt": String(localized: "Erledigt")
        case "Demo-geplant": String(localized: "Geplant")
        case "Demo-Terminbestätigung": String(localized: "Bestätigt")
        default: sourceStatus
        }
    }
}

extension PathNode {
    var displayTitle: String {
        title == "Demo-Medikamentenplan" ? String(localized: "Medikamentenplan") : title
    }

    var displayDetail: String {
        guard let history else {
            return proposalID != nil ? RecordPresentation.shortDetail(detail) : detail
        }
        if let session = history.sessionNumber { return String(localized: "Einheit \(session) von 6") }
        if history.draftKind != nil { return "" }
        if history.category == .lifeEvent { return "" }
        if history.category == .medicationEvidence { return String(localized: "Präparat nicht angegeben.") }
        return RecordPresentation.shortDetail(detail)
    }
}

extension PlanProposal {
    var displayTitle: String {
        title == "Demo-Medikamentenplan" ? String(localized: "Medikamentenplan") : title
    }
    var displayDetail: String {
        switch kind {
        case .medication: String(localized: "Zeitplan prüfen.")
        case .clarification: String(localized: "Dosis, Zeiten und Dauer fehlen.")
        default: RecordPresentation.shortDetail(detail)
        }
    }
}

extension AppointmentRecord {
    var displayLocation: String {
        location == "Fiktive Ordination/Praxis · genauer Ort nicht angegeben" ? "" : location
    }
    var displayPreparation: String {
        let sourceAppointments = ["P217-1", "P218-1", "P219-1", "P221-1", "P222-1"]
        let fromPath = sourceAppointments.contains { id == LifePathSeed.stableID($0 + "-appointment") }
        return fromPath || provenance.localizedCaseInsensitiveContains("synthetisch")
            ? RecordPresentation.shortDetail(preparation) : preparation
    }
}

extension MedicationSchedule {
    var displayTitle: String {
        title == "Demo-Präparat A — kein echtes Arzneimittel" ? String(localized: "Medikamentenplan") : title
    }
    var displayInstruction: String {
        title == "Demo-Präparat A — kein echtes Arzneimittel" ? "" : instruction
    }
}

extension MedicationOccurrence {
    var displayAmount: String { amount == "1 Demo-Einheit" ? "" : amount }
}

private enum RecordPresentation {
    static func sourceTitle(_ title: String, id: UUID) -> String {
        if id == LifePathSeed.stableID("life-path-33-source") { return String(localized: "Lebensverlauf") }
        if id == LifePathSeed.stableID("vaccination-pass-source") || title == "Impfpass.pdf · separates Testdokument" {
            return "Impfpass.pdf"
        }
        switch title {
        case "Demo A · vollständige Entlassungsunterlage", "Entlassungsbrief": return String(localized: "Entlassungsbrief")
        case "Demo B · unvollständige Medikationsangabe", "Medikationsangaben": return String(localized: "Medikationsangaben")
        case "Demo C · fachfremder Text", "Weitere Unterlage": return String(localized: "Weitere Unterlage")
        case "demo-discharge-navigation.pdf": return String(localized: "Entlassungsbrief")
        case "33 Jahre · synthetische Textvorlage": return String(localized: "Lebensverlauf")
        default: return title
        }
    }


    static func shortDetail(_ value: String) -> String {
        var text = value.components(separatedBy: ";").first ?? value
        text = text.components(separatedBy: ". ").first ?? text
        let replacements: [(String, String)] = [
            ("Fiktive Geburtsmesswerte: ", ""), ("Fiktive dokumentierte ", ""), ("Fiktiver historischer ", ""),
            ("Fiktive patientenseitige ", ""), ("Fiktiv gemeldeter ", "Gemeldeter "),
            ("Fiktive ", ""), ("Fiktiver ", ""), ("Fiktives ", ""), ("Fiktiv ", ""),
            ("fiktive ", ""), ("fiktiver ", ""), ("fiktives ", ""), ("fiktiv ", ""),
            ("fiktiven ", ""), ("fiktivem ", ""), ("ausdrücklich im ärztlichen Befund", "im ärztlichen Befund"),
            ("ausdrücklich im Ambulanzbrief genannt", "im Ambulanzbrief genannt"),
            ("ohne erfundene Dioptrienwerte", ""), ("im Demo vereinbart", "vereinbart"),
            ("Dokumentierte ", ""), ("Dokumentierter ", "")
        ]
        for (old, new) in replacements { text = text.replacingOccurrences(of: old, with: new) }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
        guard !["demo", "fiktiv", "synthet", "szenario", "beispiel"].contains(where: { folded.contains($0) }) else { return "" }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        return text.prefix(1).uppercased() + String(text.dropFirst())
    }
}
