import CryptoKit
import Foundation
import Observation
import SwiftData

@Model
final class SoviSnapshot {
    @Attribute(.unique) var key: String
    var payload: Data

    init(key: String = "local-state", payload: Data) {
        self.key = key
        self.payload = payload
    }
}

/// One versioned snapshot keeps the prototype small while maintaining separate
/// typed records, stable identities and explicit transactional commands.
@MainActor
@Observable
final class SoviStore {
    private(set) var state: AppState
    var errorMessage: String?
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let snapshot: SoviSnapshot
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let extractor: any PlanExtractor

    init(
        container: ModelContainer,
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        extractor: any PlanExtractor = DemoPlanExtractor()
    ) throws {
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.clock = clock
        self.extractor = extractor
        let descriptor = FetchDescriptor<SoviSnapshot>()
        let stored = try context.fetch(descriptor)
        guard stored.count <= 1 else { throw SoviError.unsupportedSchema }
        if let snapshot = stored.first {
            let decoded = try JSONDecoder().decode(AppState.self, from: snapshot.payload)
            guard decoded.schemaVersion == 1 else { throw SoviError.unsupportedSchema }
            self.state = decoded
            self.snapshot = snapshot
            var restoredCalendar = calendar
            restoredCalendar.timeZone = TimeZone(identifier: decoded.fixtureTimeZoneIdentifier) ?? calendar.timeZone
            self.calendar = restoredCalendar
            let updated = try VaccinationPassSeed.updatingDemo(decoded, now: clock())
            if updated != decoded { try commit(updated) }
        } else {
            let initial = try Self.seed(now: clock(), calendar: calendar)
            let row = SoviSnapshot(payload: try JSONEncoder().encode(initial))
            self.state = initial
            self.snapshot = row
            self.calendar = calendar
            context.insert(row)
            try context.save()
        }
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([SoviSnapshot.self])
        let configuration = ModelConfiguration(
            "SoviLocal", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    var now: Date { clock() }
    /// Persistent array order never changes because a status changed.
    var nodes: [PathNode] { state.nodes }

    func node(id: UUID) -> PathNode? { state.nodes.first { $0.id == id } }
    func document(id: UUID) -> SourceDocument? { state.documents.first { $0.id == id } }
    func evidence(for node: PathNode) -> [EvidenceReference] { node.evidence }

    @discardableResult
    func fixture(_ id: String) throws -> SourceDocument {
        let identifier = id.uppercased()
        if let existing = state.documents.first(where: { $0.fixtureID == identifier }) { return existing }
        let text = try DemoFixtures.text(identifier, anchor: state.fixtureEpoch, calendar: calendar)
        return try importDocument(text, title: DemoFixtures.title(identifier), fixtureID: identifier)
    }

    @discardableResult
    func importText(_ text: String, title: String, pdfData: Data? = nil, pageSpans: [DocumentPageSpan]? = nil) throws -> SourceDocument {
        try importDocument(text, title: title, fixtureID: nil, pdfData: pdfData, pageSpans: pageSpans)
    }

    func perform(_ command: AppCommand) throws {
        do {
            var updated = state
            switch command {
            case .useCaseDocument(let id):
                guard let document = updated.documents.first(where: { $0.id == id }) else { throw SoviError.missingRecord }
                let recommendations = DischargeNavigationExtractor.recommendations(in: document)
                guard !recommendations.isEmpty else { throw SoviError.invalidInput(String(localized: "Keine unterstützte ausdrückliche Empfehlung gefunden. Du kannst den Brief ansehen oder die behandelnde Stelle fragen.")) }
                var progress = updated.demoScenarios?["hospital"] ?? DemoScenarioProgress(scenario: .hospital)
                if progress.preparation?.sourceDocumentID == id { return }
                var prep = CasePreparation()
                prep.sourceDocumentID = id; prep.recommendations = recommendations
                let time = progress.answers.dropFirst().first
                progress.answers = [recommendations.map { $0.evidence.quote }.joined(separator: "\n")] + (time.map { [$0] } ?? [])
                progress.preparation = prep; progress.saved = false
                progress.history.append(ConversationTurn(role: "user", text: String(localized: "Dokument ausgewählt: \(document.title)"), date: now))
                progress.history.append(ConversationTurn(role: "assistant", text: String(localized: "Ich habe ausdrückliche Empfehlungen gefunden. Bitte prüfe die Zitate im Original, bevor du sie übernimmst."), date: now))
                if updated.demoScenarios == nil { updated.demoScenarios = [:] }
                updated.demoScenarios?["hospital"] = progress

            case .reviewCaseRecommendation(let id, let reviewed):
                guard var progress = updated.demoScenarios?["hospital"], !progress.saved,
                      var prep = progress.preparation,
                      let index = prep.recommendations.firstIndex(where: { $0.id == id }),
                      let source = updated.documents.first(where: { $0.id == prep.sourceDocumentID }),
                      DischargeNavigationExtractor.recommendations(in: source).contains(where: { $0.id == id }) else { throw SoviError.invalidAction }
                prep.recommendations[index].reviewed = reviewed; progress.preparation = prep
                updated.demoScenarios?["hospital"] = progress

            case .restartCaseQuestions:
                guard var progress = updated.demoScenarios?["care"] else { throw SoviError.missingRecord }
                var prep = progress.preparation ?? CasePreparation()
                prep.answers = [:]; prep.checkedDocuments = []; progress.preparation = prep
                progress.history.append(ConversationTurn(role: "user", text: String(localized: "Angaben zum Antrag ändern"), date: now))
                if let question = prep.nextQuestion(for: progress) { progress.history.append(ConversationTurn(role: "assistant", text: question.text, date: now)) }
                updated.demoScenarios?["care"] = progress

            case .answerCaseQuestion(let key, let value):
                guard var progress = updated.demoScenarios?["care"] else { throw SoviError.missingRecord }
                var prep = progress.preparation ?? CasePreparation()
                guard let question = prep.nextQuestion(for: progress), question.key == key,
                      let choice = question.choices.first(where: { $0.0 == value }) else { throw SoviError.invalidAction }
                prep.answers[key] = value
                progress.history.append(ConversationTurn(role: "user", text: choice.1, date: now))
                progress.preparation = prep
                progress.history.append(ConversationTurn(role: "assistant", text: prep.nextQuestion(for: progress)?.text ?? String(localized: "Jetzt können wir die zuständige Stelle, Angaben und Unterlagen gemeinsam prüfen."), date: now))
                updated.demoScenarios?["care"] = progress

            case .setCaseDocument(let scenario, let key, let present):
                guard var progress = updated.demoScenarios?[scenario.rawValue] else { throw SoviError.missingRecord }
                var prep = progress.preparation ?? CasePreparation()
                guard prep.documentItems(for: progress).contains(where: { $0.id == key }) else { throw SoviError.invalidAction }
                if present { prep.checkedDocuments.insert(key) } else { prep.checkedDocuments.remove(key) }
                progress.preparation = prep; updated.demoScenarios?[scenario.rawValue] = progress

            case .setCaseApplicant(let scenario, let id):
                guard updated.formPeople?.contains(where: { $0.id == id }) == true,
                      var progress = updated.demoScenarios?[scenario.rawValue] else { throw SoviError.missingRecord }
                var prep = progress.preparation ?? CasePreparation()
                if prep.applicantID != id { prep.checkedDocuments.remove("signatures") }
                prep.applicantID = id; progress.preparation = prep
                updated.demoScenarios?[scenario.rawValue] = progress

            case .startScenario(let scenario):
                if var existing = updated.demoScenarios?[scenario.rawValue] {
                    guard [.care, .hospital].contains(scenario), existing.preparation == nil else { return }
                    existing.preparation = CasePreparation(); updated.demoScenarios?[scenario.rawValue] = existing
                    break
                }
                if updated.demoScenarios == nil { updated.demoScenarios = [:] }
                var progress = DemoScenarioProgress(scenario: scenario)
                if [.care, .hospital].contains(scenario) { progress.preparation = CasePreparation() }
                progress.history = [ConversationTurn(role: "assistant", text: progress.question, date: now)]
                updated.demoScenarios?[scenario.rawValue] = progress

            case .answerScenario(let scenario, let answer):
                guard var progress = updated.demoScenarios?[scenario.rawValue], !progress.finished else { throw SoviError.invalidAction }
                let normalized = try progress.normalizedAnswer(answer)
                progress.answers.append(normalized)
                progress.history.append(ConversationTurn(role: "user", text: normalized == DemoScenarioProgress.sampleLetter ? normalized : answer, date: now))
                let reply = progress.finished ? progress.preparation?.nextQuestion(for: progress)?.text ?? progress.summary : progress.question
                progress.history.append(ConversationTurn(role: "assistant", text: reply, date: now))
                updated.demoScenarios?[scenario.rawValue] = progress

            case .saveScenarioSteps(let scenario):
                guard var progress = updated.demoScenarios?[scenario.rawValue], progress.finished else { throw SoviError.invalidAction }
                guard !progress.saved else { return }
                if scenario == .care, let prep = progress.preparation, prep.nextQuestion(for: progress) != nil { throw SoviError.invalidAction }
                if scenario == .hospital {
                    guard let prep = progress.preparation, prep.sourceDocumentID != nil,
                          prep.recommendations.contains(where: \.reviewed) else { throw SoviError.invalidAction }
                }
                for (index, title) in progress.steps.enumerated() {
                    let id = progress.taskID(index)
                    guard !updated.nodes.contains(where: { $0.id == id }) else { throw SoviError.invalidAction }
                    let detail = progress.history.filter { $0.role == "user" }.map(\.text).joined(separator: "\n") + "\n\n" + progress.summary + "\n\n" + progress.sources.map { $0.0 + ": " + $0.1 }.joined(separator: "\n")
                    let evidence = scenario == .hospital ? (index == 0 ? progress.preparation?.recommendations.filter(\.reviewed).map(\.evidence) : progress.preparation?.recommendations.filter(\.reviewed).dropFirst(index - 1).first.map { [$0.evidence] }) ?? [] : []
                    updated.nodes.append(PathNode(id: id, kind: .task, title: title, detail: detail, evidence: evidence, createdAt: now))
                }
                progress.saved = true
                updated.demoScenarios?[scenario.rawValue] = progress

            case .startWelcome:
                guard updated.welcome == nil else { return }
                let person = FormPerson(isSelf: true)
                updated.formPeople = (updated.formPeople ?? []) + [person]
                updated.welcome = WelcomeProgress(personID: person.id, history: [ConversationTurn(role: "assistant", text: PersonField.firstName.question, date: now)])

            case .answerWelcome(let answer, let finish):
                guard var welcome = updated.welcome, !welcome.completed,
                      let personIndex = updated.formPeople?.firstIndex(where: { $0.id == welcome.personID }) else { throw SoviError.invalidAction }
                let value = answer?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let field = welcome.field {
                    if let value, let error = field.validate(value) { throw SoviError.invalidInput(error) }
                    if let value, !value.isEmpty { updated.formPeople?[personIndex].values[field.rawValue] = value }
                }
                welcome.history.append(ConversationTurn(role: "user", text: value ?? String(localized: finish ? "Später ergänzen" : "Überspringen"), date: now))
                welcome.step = finish ? WelcomeProgress.fields.count + 2 : welcome.step + 1
                welcome.completed = welcome.step >= WelcomeProgress.fields.count + 2
                welcome.history.append(ConversationTurn(role: "assistant", text: welcome.completed ? String(localized: "Danke! Deine Angaben bleiben auf diesem Gerät. Du kannst sie für jeden Formularentwurf prüfen und ändern. Wobei kann ich dir helfen?") : welcome.question, date: now))
                updated.welcome = welcome

            case .savePerson(let person):
                guard person.label.count <= 200, person.values.count <= PersonField.allCases.count,
                      person.values.keys.allSatisfy({ PersonField(rawValue: $0) != nil }) else { throw SoviError.invalidAction }
                for field in PersonField.allCases {
                    if let error = field.validate(person.values[field.rawValue] ?? "") { throw SoviError.invalidInput(error) }
                }
                var people = updated.formPeople ?? []
                if let index = people.firstIndex(where: { $0.id == person.id }) { people[index] = person }
                else { people.append(person) }
                updated.formPeople = people

            case .saveFormDraft(let key, let draft):
                guard draft.values.count <= 200, draft.values.values.allSatisfy({ $0.count <= 2000 }),
                      key == draft.storageKey,
                      updated.formPeople?.contains(where: { $0.id == draft.personID }) == true else { throw SoviError.invalidAction }
                if let selections = draft.selections, !selections.isEmpty {
                    guard draft.formID == "pflegegeld", selections.count == 1,
                          ["01", "02", "03"].contains(selections["Antrag Pflg"] ?? "") else { throw SoviError.invalidAction }
                }
                if let raw = draft.caseScenario {
                    guard DemoScenario(rawValue: raw) != nil, let progress = updated.demoScenarios?[raw],
                          progress.preparation?.applicantID == draft.personID,
                          progress.preparation?.formIDs(for: progress).contains(draft.formID) == true else { throw SoviError.invalidAction }
                }
                if updated.formDrafts == nil { updated.formDrafts = [:] }
                updated.formDrafts?[key] = draft

            case .setTask(let id, let status):
                guard let index = updated.nodes.firstIndex(where: { $0.id == id }) else { throw SoviError.missingRecord }
                guard updated.nodes[index].kind == .task else { throw SoviError.invalidAction }
                let canonicalID = updated.nodes[index].history?.linkedTaskID ?? id
                for i in updated.nodes.indices where updated.nodes[i].id == canonicalID || updated.nodes[i].history?.linkedTaskID == canonicalID {
                    updated.nodes[i].taskStatus = status
                }

            case .markRead(let id, let read):
                guard let index = updated.nodes.firstIndex(where: { $0.id == id }) else { throw SoviError.missingRecord }
                guard updated.nodes[index].kind == .information else { throw SoviError.invalidAction }
                updated.nodes[index].informationRead = read

            case .approveProposal(let documentID, let proposalID, let revision, let editedTitle):
                guard let documentIndex = updated.documents.firstIndex(where: { $0.id == documentID }),
                      let proposalIndex = updated.documents[documentIndex].proposals.firstIndex(where: { $0.id == proposalID }) else {
                    throw SoviError.missingRecord
                }
                let proposal = updated.documents[documentIndex].proposals[proposalIndex]
                guard proposal.status == .pending else { return }
                guard proposal.revision == revision else { throw SoviError.staleProposal }
                let title = try Self.validTitle(editedTitle ?? proposal.title)
                let node = try approvedNode(proposal, title: title, state: &updated)
                updated.nodes.append(node)
                updated.documents[documentIndex].proposals[proposalIndex].status = .approved
                updated.documents[documentIndex].proposals[proposalIndex].approvedNodeID = node.id
                updated.documents[documentIndex].proposals[proposalIndex].reviewedAt = now
                updated.documents[documentIndex].proposals[proposalIndex].revision += 1

            case .rejectProposal(let documentID, let proposalID, let revision):
                guard let documentIndex = updated.documents.firstIndex(where: { $0.id == documentID }),
                      let proposalIndex = updated.documents[documentIndex].proposals.firstIndex(where: { $0.id == proposalID }) else {
                    throw SoviError.missingRecord
                }
                let proposal = updated.documents[documentIndex].proposals[proposalIndex]
                guard proposal.status == .pending else { return }
                guard proposal.revision == revision else { throw SoviError.staleProposal }
                updated.documents[documentIndex].proposals[proposalIndex].status = .rejected
                updated.documents[documentIndex].proposals[proposalIndex].reviewedAt = now
                updated.documents[documentIndex].proposals[proposalIndex].revision += 1

            case .addNode(let kind, let title, let detail, let date, let location, let status, let operationID):
                guard !updated.processedOperationIDs.contains(operationID) else { return }
                guard [.event, .task, .appointment].contains(kind) else { throw SoviError.invalidAction }
                let cleanTitle = try Self.validTitle(title)
                guard detail.count <= 12_000, location.count <= 500 else {
                    throw SoviError.invalidInput(String(localized: "Der Text ist für diesen Eintrag zu lang."))
                }
                var node = PathNode(kind: kind, title: cleanTitle, detail: detail, createdAt: now, date: date)
                if kind == .appointment {
                    guard let date else { throw SoviError.invalidInput(String(localized: "Bitte ein Datum angeben.")) }
                    let record = AppointmentRecord(
                        title: cleanTitle, date: date, location: location, status: status,
                        provenance: Self.provenance(for: status), preparation: detail, createdAt: now, updatedAt: now
                    )
                    node.appointmentID = record.id
                    updated.appointments.append(record)
                }
                updated.nodes.append(node)
                updated.processedOperationIDs.insert(operationID)

            case .editAppointment(var record):
                guard let index = updated.appointments.firstIndex(where: { $0.id == record.id }) else { throw SoviError.missingRecord }
                record.title = try Self.validTitle(record.title)
                guard record.location.count <= 500, record.preparation.count <= 12_000 else {
                    throw SoviError.invalidInput(String(localized: "Der Text ist für diesen Termin zu lang."))
                }
                record.createdAt = updated.appointments[index].createdAt
                record.updatedAt = now
                // The prototype records the user's report, never a provider confirmation.
                record.provenance = Self.provenance(for: record.status)
                updated.appointments[index] = record
                if let nodeIndex = updated.nodes.firstIndex(where: { $0.appointmentID == record.id }) {
                    updated.nodes[nodeIndex].title = record.title
                    updated.nodes[nodeIndex].date = record.date
                }

            case .recordMedication(let scheduleID, let occurrenceID, let log):
                guard let scheduleIndex = updated.schedules.firstIndex(where: { $0.id == scheduleID }),
                      let occurrenceIndex = updated.schedules[scheduleIndex].occurrences.firstIndex(where: { $0.id == occurrenceID }) else {
                    throw SoviError.missingRecord
                }
                let oldValue = updated.schedules[scheduleIndex].occurrences[occurrenceIndex].log
                guard oldValue != log else { return }
                updated.schedules[scheduleIndex].occurrences[occurrenceIndex].corrections.append(
                    MedicationCorrection(previous: oldValue, value: log, date: now)
                )
                updated.schedules[scheduleIndex].occurrences[occurrenceIndex].log = log

            case .saveLifeDraft(let kind, let text):
                guard text.count <= 100_000 else { throw SoviError.invalidInput(String(localized: "Der Entwurf ist zu lang.")) }
                if updated.lifeDrafts == nil { updated.lifeDrafts = [:] }
                updated.lifeDrafts?[kind.rawValue] = text

            case .saveDraft(let text):
                guard text.count <= 100_000 else { throw SoviError.invalidInput(String(localized: "Der Entwurf ist zu lang.")) }
                let id = updated.draft?.id ?? UUID()
                updated.draft = AdministrativeDraft(id: id, text: text, updatedAt: now)

            case .appendConversation(let role, let text):
                guard ["user", "assistant"].contains(role), text.count <= 20_000 else { throw SoviError.invalidAction }
                updated.conversation.append(ConversationTurn(role: role, text: text, date: now))

            case .saveComposer(let text):
                guard text.count <= 20_000 else { throw SoviError.invalidInput(String(localized: "Die Nachricht ist zu lang.")) }
                updated.composerDraft = text

            case .setFocusContext(let id):
                if let id, !updated.nodes.contains(where: { $0.id == id }) { throw SoviError.missingRecord }
                updated.focusContextID = id

            case .setPreferences(let notifications, let spokenReplies, let straightPath):
                if let notifications { updated.notificationsEnabled = notifications }
                if let spokenReplies { updated.spokenReplies = spokenReplies }
                if let straightPath { updated.straightPath = straightPath }

            case .deleteLocalData:
                // Keep an empty persisted snapshot so next launch never silently reseeds.
                updated = AppState(fixtureEpoch: now, fixtureTimeZoneIdentifier: calendar.timeZone.identifier)

            case .reloadDemo:
                updated = try Self.seed(now: now, calendar: calendar)
            }
            try commit(updated)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func applicationDraftTemplate() -> String {
        if state.lifeScenario != nil {
            return """
            Entwurf · nicht eingereicht

            Name: [BITTE ERGÄNZEN]
            Adresse / Kontakt: [BITTE ERGÄNZEN]
            Empfänger: [BITTE ERGÄNZEN]

            Betreff: Anfrage zur Kostenerstattung

            Sehr geehrte Damen und Herren,

            ich bitte um Informationen zur Kostenerstattung für Physiotherapie und zu den benötigten Unterlagen.

            Referenzen:
            - Verordnung vom 01.10.2026
            - Honorarnote für vier Einheiten vom 29.10.2026
            - Zahlungsnachweis vom 30.10.2026
            Quelle: Lebensverlauf

            Betrag: [NICHT ANGEGEBEN – PRÜFEN]
            Mein Anliegen: [BITTE ERGÄNZEN]

            Mit freundlichen Grüßen
            [NAME ERGÄNZEN]
            """
        }
        let references = state.documents.map { "- \($0.displayTitle)" }.joined(separator: "\n")
        return """
        Entwurf · nicht eingereicht

        Name: [BITTE ERGÄNZEN]
        Adresse / Kontakt: [BITTE ERGÄNZEN]
        Empfänger: [BITTE ERGÄNZEN]

        Betreff: Anfrage

        Sehr geehrte Damen und Herren,

        ich bitte um Informationen zu meinem Anliegen und den benötigten Unterlagen.

        Mein Anliegen: [BITTE ERGÄNZEN]

        Referenzen:
        \(references.isEmpty ? "[UNTERLAGEN ERGÄNZEN]" : references)

        Mit freundlichen Grüßen
        [NAME ERGÄNZEN]
        """
    }

    private func importDocument(_ text: String, title: String, fixtureID: String?, pdfData: Data? = nil, pageSpans: [DocumentPageSpan]? = nil) throws -> SourceDocument {
        do {
            let normalized = DemoPlanExtractor.normalized(text)
            guard !normalized.isEmpty else { throw SoviError.invalidInput(String(localized: "Kein lesbarer Text gefunden.")) }
            guard normalized.utf8.count <= 2_000_000 else { throw SoviError.invalidInput(String(localized: "Textdatei zu groß. Maximal 2 MB.")) }
            guard (pdfData?.count ?? 0) <= 5 * 1024 * 1024 else { throw SoviError.invalidInput(String(localized: "Leere Datei oder größer als 5 MB.")) }
            if let pageSpans {
                guard pdfData != nil, pageSpans.count <= 100,
                      pageSpans.allSatisfy({ (1...100).contains($0.pageNumber) && $0.utf16Start >= 0 && $0.utf16Length >= 0 && $0.utf16Start <= (normalized as NSString).length - $0.utf16Length }) else { throw SoviError.invalidAction }
            }
            let fingerprint = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
            if let index = state.documents.firstIndex(where: { $0.originalFingerprint == fingerprint }) {
                if state.documents[index].importedPDFData == nil, let pdfData {
                    var updated = state; updated.documents[index].importedPDFData = pdfData; updated.documents[index].pageSpans = pageSpans; try commit(updated)
                }
                return state.documents[index]
            }
            var document = SourceDocument(title: try Self.validTitle(title), text: normalized,
                                          importedAt: now, originalFingerprint: fingerprint, fixtureID: fixtureID)
            document.importedPDFData = pdfData
            document.pageSpans = pageSpans
            document.proposals = try extractor.extract(document: document, anchor: state.fixtureEpoch, calendar: calendar)
            var updated = state
            updated.documents.append(document)
            try commit(updated)
            return document
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func approvedNode(_ proposal: PlanProposal, title: String, state updated: inout AppState) throws -> PathNode {
        var node = PathNode(kind: .task, title: title, detail: proposal.detail,
                            evidence: proposal.evidence, createdAt: now, proposalID: proposal.id)
        switch proposal.kind {
        case .task, .clarification:
            break
        case .appointment:
            // A source proposal cannot imply an externally confirmed booking.
            throw SoviError.invalidAction
        case .medication:
            // Re-extract trusted known fixture text. Never trust arbitrary proposal fields.
            guard let sourceID = proposal.evidence.first?.documentID,
                  let source = updated.documents.first(where: { $0.id == sourceID }),
                  let matched = try DemoPlanExtractor().extract(document: source, anchor: updated.fixtureEpoch, calendar: calendar)
                    .first(where: { $0.kind == .medication }),
                  let instruction = matched.medicationInstruction,
                  let start = matched.medicationStart, let end = matched.medicationEnd,
                  proposal.medicationInstruction == instruction,
                  proposal.medicationStart == start, proposal.medicationEnd == end,
                  proposal.evidence.map(\.quote) == matched.evidence.map(\.quote)
            else { throw SoviError.incompleteInstruction }
            var occurrences: [MedicationOccurrence] = []
            for dayOffset in 0..<3 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start), day <= end else {
                    throw SoviError.incompleteInstruction
                }
                for hour in [8, 20] {
                    guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else {
                        throw SoviError.incompleteInstruction
                    }
                    occurrences.append(MedicationOccurrence(date: date, amount: "1 Demo-Einheit"))
                }
            }
            let schedule = MedicationSchedule(
                title: "Demo-Präparat A — kein echtes Arzneimittel", instruction: instruction,
                evidence: proposal.evidence, occurrences: occurrences, timeZoneIdentifier: calendar.timeZone.identifier
            )
            updated.schedules.append(schedule)
            node.kind = .medication
            node.scheduleID = schedule.id
        }
        return node
    }

    private func commit(_ updated: AppState) throws {
        let encoded = try JSONEncoder().encode(updated)
        snapshot.payload = encoded
        do {
            try context.save()
            state = updated
            errorMessage = nil
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func validTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 250 else {
            throw SoviError.invalidInput(String(localized: "Bitte einen Titel eingeben (max. 250 Zeichen)."))
        }
        return title
    }

    private static func provenance(for status: AppointmentStatus) -> String {
        switch status {
        case .requestDraft: "Anfrageentwurf"
        case .confirmed: "Von dir bestätigt"
        case .cancelled: "Von dir als abgesagt erfasst"
        }
    }

    private static func seed(now: Date, calendar: Calendar) throws -> AppState {
        try LifePathSeed.state(now: now, calendar: calendar)
    }
}
