import CryptoKit
import Foundation
import Observation
import SwiftData

struct ChatDocumentImportResult {
    let document: SourceDocument
    let eventIDs: [UUID]
    let addedEventIDs: [UUID]
    let reply: String
}

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

    var nextChatDate: Date {
        let previous = max(state.conversation.last?.date ?? .distantPast, state.latestOnlineTurnAt ?? .distantPast)
        return max(now, previous.addingTimeInterval(0.0001))
    }
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

    /// Save the local attachment, its historical events, and the chat receipt in one snapshot.
    func importChatAttachment(_ input: CaseDocumentImport.Contents, title: String, language: ChatLanguage) throws -> ChatDocumentImportResult {
        do {
            var updated = state
            let document = try prepareDocument(input.text, title: title, fixtureID: nil, pdfData: input.pdf, pageSpans: input.pageSpans, in: &updated)
            let importedAt = now
            let recordedBefore = Set(state.nodes.map(\.id))
            let eventIDs: [UUID]
            var unreadableRows = 0
            if let pass = VaccinationImport.review(document, calendar: updated.pathCalendar, asOf: importedAt) {
                eventIDs = VaccinationImport.record(pass.entries, from: document, in: &updated, now: importedAt)
                unreadableRows = pass.unreadableRows
            } else {
                let events = BefundReader.lifeEvents(in: document, calendar: updated.pathCalendar, asOf: importedAt, language: language.rawValue)
                eventIDs = events.map(\.id)
                for event in events {
                    let evidence = [event.evidence] + event.modalityEvidence
                    if let index = updated.nodes.firstIndex(where: { $0.id == event.id }) {
                        guard updated.nodes[index].kind == .event, updated.nodes[index].evidence.contains(where: { $0.documentID == document.id })
                        else { throw SoviError.invalidAction }
                        // Reattaching a PDF can supply page numbers previously unavailable from text.
                        let otherSources = updated.nodes[index].evidence.filter { $0.documentID != document.id }
                        updated.nodes[index].evidence = evidence + otherSources
                    } else {
                        updated.nodes.append(PathNode(id: event.id, kind: .event, title: event.title, detail: event.evidence.quote,
                                                      chapter: 4, evidence: evidence, createdAt: importedAt, date: event.date))
                    }
                }
            }
            let addedIDs = eventIDs.filter { !recordedBefore.contains($0) }
            var reply: String
            if eventIDs.isEmpty {
                reply = language.text("Dokument gespeichert. Ich habe kein eindeutig datiertes Ereignis gefunden.")
            } else if addedIDs.isEmpty {
                reply = language.text("Diese Ereignisse stehen bereits auf deinem Pfad.")
            } else if addedIDs.count == 1 {
                reply = language.text("Ich habe ein Ereignis in deinen Pfad eingetragen.")
            } else {
                reply = language.localized("Ich habe \(addedIDs.count) Ereignisse in deinen Pfad eingetragen.")
            }
            if unreadableRows > 0 { reply += " " + language.text("Bitte prüfe unvollständige Impfzeilen im Original.") }
            updated.conversation.append(ConversationTurn(role: "user", text: document.title, date: importedAt, attachmentDocumentID: document.id))
            updated.conversation.append(ConversationTurn(role: "assistant", text: reply, date: importedAt,
                                                        attachmentEventIDs: eventIDs, replyDocumentID: document.id))
            updated.focusContextID = nil
            updated.discussedDocumentID = document.id
            try commit(updated)
            return ChatDocumentImportResult(document: document, eventIDs: eventIDs, addedEventIDs: addedIDs, reply: reply)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func perform(_ command: AppCommand) throws {
        do {
            var updated = state
            switch command {
            case .linkCareReport(let id, let language):
                guard let doc = updated.documents.first(where: { $0.id == id }),
                      BefundReader.review(doc, language: language.rawValue)?.actions.contains(where: \.isCareRequest) == true else {
                    throw SoviError.invalidAction
                }
                var progress = updated.demoScenarios?["care"] ?? DemoScenarioProgress(scenario: .care)
                progress.language = language
                var prep = progress.preparation ?? CasePreparation()
                prep.sourceDocumentID = id
                progress.preparation = prep
                if progress.history.isEmpty { progress.history.append(ConversationTurn(role: "assistant", text: progress.question, date: now)) }
                if updated.demoScenarios == nil { updated.demoScenarios = [:] }
                updated.demoScenarios?["care"] = progress
            case .leaveDocumentDiscussion:
                guard updated.discussedDocumentID != nil else { return }
                updated.discussedDocumentID = nil
            case .beginReportQuestion(let id, let turn):
                guard updated.documents.contains(where: { $0.id == id }), turn.role == "user", !turn.text.isEmpty,
                      !updated.conversation.contains(where: { $0.id == turn.id }) else { throw SoviError.invalidAction }
                updated.conversation.append(turn)
                updated.discussedDocumentID = id; updated.focusContextID = nil; updated.composerDraft = ""
            case .discussDocument(let id, let question, let reply, let eventIDs, let questionID, let replyID):
                if let id, !updated.documents.contains(where: { $0.id == id }) { throw SoviError.missingRecord }
                guard (question?.count ?? 0) <= 20_000, !reply.isEmpty, reply.count <= 20_000 else { throw SoviError.invalidAction }
                if let eventIDs {
                    guard let id, Set(eventIDs).count == eventIDs.count, eventIDs.allSatisfy({ eventID in
                        updated.nodes.contains { $0.id == eventID && $0.evidence.contains { $0.documentID == id } }
                    }) else { throw SoviError.invalidAction }
                }
                if let question { updated.conversation.append(ConversationTurn(id: questionID ?? UUID(), role: "user", text: question, date: now)) }
                updated.conversation.append(ConversationTurn(id: replyID ?? UUID(), role: "assistant", text: reply, date: now,
                                                            attachmentEventIDs: eventIDs, replyDocumentID: id))
                updated.discussedDocumentID = id
                updated.focusContextID = nil
                updated.composerDraft = ""
            case .adoptBefundActions(let id, let selected, let language):
                try BefundReader.apply(documentID: id, selectedIDs: selected, language: language, to: &updated, now: now)
            case .importVaccinations(let id, let selected):
                try VaccinationImport.apply(documentID: id, selectedIDs: selected, to: &updated, now: now)
            case .useCaseDocument(let id):
                guard let document = updated.documents.first(where: { $0.id == id }) else { throw SoviError.missingRecord }
                let recommendations = DischargeNavigationExtractor.recommendations(in: document)
                guard !recommendations.isEmpty else { throw SoviError.invalidInput(String(localized: "Keine unterstützte ausdrückliche Empfehlung gefunden. Du kannst den Brief ansehen oder die behandelnde Stelle fragen.")) }
                var progress = updated.demoScenarios?["hospital"] ?? DemoScenarioProgress(scenario: .hospital)
                if progress.preparation?.sourceDocumentID == id { return }
                var prep = CasePreparation(applicantID: progress.preparation?.applicantID)
                prep.sourceDocumentID = id; prep.recommendations = recommendations
                let time = progress.answers.dropFirst().first
                progress.answers = [recommendations.map { $0.evidence.quote }.joined(separator: "\n")] + (time.map { [$0] } ?? [])
                progress.preparation = prep; progress.saved = false
                progress.history.append(ConversationTurn(role: "user", text: progress.replyLanguage.localized("Dokument ausgewählt: \(document.displayTitle)"), date: now))
                progress.history.append(ConversationTurn(role: "assistant", text: progress.replyLanguage.text("Ich habe ausdrückliche Empfehlungen gefunden. Bitte prüfe die Zitate im Original, bevor du sie übernimmst."), date: now))
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
                progress.history.append(ConversationTurn(role: "assistant", text: prep.nextQuestion(for: progress)?.text ?? progress.replyLanguage.text("Jetzt können wir die zuständige Stelle, Angaben und Unterlagen gemeinsam prüfen."), date: now))
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

            case .startScenario(let scenario, let language, let opening):
                let existing = updated.demoScenarios?[scenario.rawValue]
                var progress = existing ?? DemoScenarioProgress(scenario: scenario)
                if let language { progress.language = language }
                if [.care, .hospital].contains(scenario), progress.preparation == nil { progress.preparation = CasePreparation() }
                if let opening, !opening.isEmpty {
                    progress.history.append(ConversationTurn(role: "user", text: opening, date: now))
                    if progress.answers.isEmpty, [.care, .health].contains(scenario), let choice = progress.recognizedChoice(opening) {
                        progress.answers.append(choice)
                    }
                }
                if existing == nil || opening != nil || (language != nil && language != existing?.language) {
                    let prompt = progress.finished ? progress.preparation?.nextQuestion(for: progress)?.text ?? progress.summary : progress.question
                    progress.history.append(ConversationTurn(role: "assistant", text: prompt, date: now))
                }
                guard existing != progress else { return }
                if updated.demoScenarios == nil { updated.demoScenarios = [:] }
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
                let reportActions = progress.preparation?.sourceDocumentID.flatMap { id in
                    updated.documents.first(where: { $0.id == id }).flatMap { BefundReader.review($0, language: progress.replyLanguage.rawValue)?.actions }
                } ?? []
                for (index, title) in progress.steps.enumerated() {
                    let id = progress.taskID(index)
                    let detail = progress.history.filter { $0.role == "user" }.map(\.text).joined(separator: "\n") + "\n\n" + progress.summary + "\n\n" + progress.sources.map { $0.0 + ": " + $0.1 }.joined(separator: "\n")
                    let evidence = scenario == .hospital ? (index == 0 ? progress.preparation?.recommendations.filter(\.reviewed).map(\.evidence) : progress.preparation?.recommendations.filter(\.reviewed).dropFirst(index - 1).first.map { [$0.evidence] }) ?? [] : []
                    if let existing = updated.nodes.first(where: { $0.id == id }) {
                        guard scenario == .hospital, existing.kind == .task,
                              evidence.contains(where: { source in existing.evidence.contains { $0.documentID == source.documentID && $0.quote == source.quote } })
                        else { throw SoviError.invalidAction }
                        continue
                    }
                    let date = reportActions.first { $0.id == id }?.date
                    updated.nodes.append(PathNode(id: id, kind: .task, title: title, detail: detail, evidence: evidence, createdAt: now, date: date))
                }
                progress.saved = true
                updated.demoScenarios?[scenario.rawValue] = progress

            case .startWelcome:
                guard updated.welcome == nil else { return }
                let person = FormPerson(isSelf: true)
                updated.formPeople = (updated.formPeople ?? []) + [person]
                var welcome = WelcomeProgress(personID: person.id)
                welcome.history = [ConversationTurn(role: "assistant", text: welcome.question, date: now)]
                updated.welcome = welcome

            case .answerWelcome(let answer, let finish, let permissionUnavailable):
                guard var welcome = updated.welcome, !welcome.completed,
                      let personIndex = updated.formPeople?.firstIndex(where: { $0.id == welcome.personID }) else { throw SoviError.invalidAction }
                var person = updated.formPeople![personIndex]
                try welcome.recordAnswer(answer, finish: finish, permissionUnavailable: permissionUnavailable, person: &person, now: now)
                updated.formPeople?[personIndex] = person
                updated.welcome = welcome

            case .answerWelcomeAddress(let address):
                guard var welcome = updated.welcome, welcome.isAddressStep, !welcome.completed,
                      let personIndex = updated.formPeople?.firstIndex(where: { $0.id == welcome.personID }) else { throw SoviError.invalidAction }
                var person = updated.formPeople![personIndex]
                try welcome.recordAnswer(address.displayText, address: address, person: &person, now: now)
                updated.formPeople?[personIndex] = person
                updated.welcome = welcome

            case .welcomeECard(let action):
                guard var welcome = updated.welcome,
                      let personIndex = updated.formPeople?.firstIndex(where: { $0.id == welcome.personID }),
                      var person = updated.formPeople?[personIndex] else { throw SoviError.invalidAction }
                try welcome.handleECard(action, person: &person, now: now)
                updated.formPeople?[personIndex] = person
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

            case .recordAttendance(let id, let attendance):
                guard let index = updated.appointments.firstIndex(where: { $0.id == id }),
                      updated.appointments[index].status != .cancelled else { throw SoviError.invalidAction }
                let day = updated.pathCalendar.startOfDay(for: updated.appointments[index].date)
                guard attendance == .unrecorded || day <= updated.pathCalendar.startOfDay(for: now) else {
                    throw SoviError.invalidInput(String(localized: "Die Teilnahme kannst du ab dem Tag des Termins eintragen."))
                }
                updated.appointments[index].attendance = attendance
                updated.appointments[index].checkInDeferredUntil = nil
                updated.appointments[index].updatedAt = now

            case .beginAttendanceCheckIn(let nodeID, let question, let userMessage):
                guard let id = updated.nodes.first(where: { $0.id == nodeID })?.appointmentID,
                      let record = updated.appointments.first(where: { $0.id == id }),
                      record.needsAttendanceCheck(at: now), !question.isEmpty, question.count <= 20_000,
                      (userMessage?.count ?? 0) <= 20_000 else { throw SoviError.invalidAction }
                updated.focusContextID = nodeID
                updated.discussedDocumentID = nil
                if let userMessage {
                    updated.conversation.append(ConversationTurn(role: "user", text: userMessage, date: now))
                    updated.composerDraft = ""
                }
                if updated.conversation.last?.attendanceQuestionID != nodeID || updated.conversation.last?.text != question {
                    updated.conversation.append(ConversationTurn(role: "assistant", text: question, date: now, attendanceQuestionID: nodeID))
                }

            case .answerAttendanceCheckIn(let nodeID, let attendance, let answer, let confirmation):
                let answeredAt = now
                guard updated.focusContextID == nodeID, updated.conversation.last?.attendanceQuestionID == nodeID,
                      let id = updated.nodes.first(where: { $0.id == nodeID })?.appointmentID,
                      let index = updated.appointments.firstIndex(where: { $0.id == id }),
                      updated.appointments[index].needsAttendanceCheck(at: answeredAt),
                      attendance != .unrecorded,
                      !answer.isEmpty, answer.count <= 20_000, !confirmation.isEmpty, confirmation.count <= 20_000
                else { throw SoviError.invalidAction }
                if let attendance {
                    updated.appointments[index].attendance = attendance
                    updated.appointments[index].checkInDeferredUntil = nil
                } else {
                    let calendar = updated.pathCalendar
                    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: answeredAt))
                    else { throw SoviError.invalidAction }
                    updated.appointments[index].checkInDeferredUntil = tomorrow
                }
                updated.appointments[index].updatedAt = answeredAt
                updated.conversation.append(ConversationTurn(role: "user", text: answer, date: answeredAt, attendanceAnswerID: nodeID))
                updated.conversation.append(ConversationTurn(role: "assistant", text: confirmation, date: answeredAt))

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

            case .saveLiveChatHistory(let data, let lastTurnAt):
                updated.liveChatHistory = data
                updated.latestOnlineTurnAt = lastTurnAt

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
                let previous = updated
                updated = try Self.seed(now: now, calendar: calendar)
                updated.conversation = previous.conversation
                updated.liveChatHistory = previous.liveChatHistory
                updated.latestOnlineTurnAt = previous.latestOnlineTurnAt
                updated.welcome = previous.welcome
                updated.formPeople = previous.formPeople
                updated.formDrafts = previous.formDrafts
                updated.demoScenarios = previous.demoScenarios
                let previousDocuments = Set(previous.documents.map(\.id))
                updated.documents = previous.documents + updated.documents.filter { !previousDocuments.contains($0.id) }
                let referencedEvents = Set(previous.conversation.flatMap { $0.attachmentEventIDs ?? [] })
                let retainedEvents = previous.nodes.filter { referencedEvents.contains($0.id) }
                updated.nodes = retainedEvents + updated.nodes.filter { !referencedEvents.contains($0.id) }
            }
            switch command {
            case .setCaseApplicant(let scenario, _), .answerScenario(let scenario, _):
                try prepareMatchedForms(in: &updated, for: scenario)
            case .answerCaseQuestion:
                try prepareMatchedForms(in: &updated, for: .care)
            case .reviewCaseRecommendation:
                try prepareMatchedForms(in: &updated, for: .hospital)
            default: break
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
            var updated = state
            let document = try prepareDocument(text, title: title, fixtureID: fixtureID, pdfData: pdfData, pageSpans: pageSpans, in: &updated)
            if updated.documents != state.documents { try commit(updated) }
            return document
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func prepareDocument(_ text: String, title: String, fixtureID: String?, pdfData: Data?, pageSpans: [DocumentPageSpan]?, in updated: inout AppState) throws -> SourceDocument {
        let normalized = DemoPlanExtractor.normalized(text)
        guard !normalized.isEmpty else { throw SoviError.invalidInput(String(localized: "Kein lesbarer Text gefunden.")) }
        guard normalized.utf8.count <= 2_000_000 else { throw SoviError.invalidInput(String(localized: "Textdatei zu groß. Maximal 2 MB.")) }
        guard (pdfData?.count ?? 0) <= 5 * 1024 * 1024 else { throw SoviError.invalidInput(String(localized: "Leere Datei oder größer als 5 MB.")) }
        if let pageSpans {
            let length = (normalized as NSString).length
            guard pdfData != nil, pageSpans.count <= 100,
                  pageSpans.allSatisfy({ (1...100).contains($0.pageNumber) && $0.utf16Start >= 0 && $0.utf16Length >= 0 && $0.utf16Start <= length - $0.utf16Length })
            else { throw SoviError.invalidAction }
        }
        let fingerprint = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        if let index = updated.documents.firstIndex(where: { existing in
            if let original = existing.importedPDFData, let pdfData { return original == pdfData }
            return existing.originalFingerprint == fingerprint
        }) {
            if updated.documents[index].importedPDFData == nil, let pdfData {
                updated.documents[index].importedPDFData = pdfData
                updated.documents[index].pageSpans = pageSpans
            } else if updated.documents[index].pageSpans == nil, let pageSpans, updated.documents[index].text == normalized {
                updated.documents[index].pageSpans = pageSpans
            }
            return updated.documents[index]
        }
        var document = SourceDocument(title: try Self.validTitle(title), text: normalized,
                                      importedAt: now, originalFingerprint: fingerprint, fixtureID: fixtureID)
        document.importedPDFData = pdfData
        document.pageSpans = pageSpans
        document.proposals = try extractor.extract(document: document, anchor: updated.fixtureEpoch, calendar: calendar)
        updated.documents.append(document)
        return document
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

    private func prepareMatchedForms(in state: inout AppState, for scenario: DemoScenario) throws {
        guard let progress = state.demoScenarios?[scenario.rawValue], progress.finished,
              let prep = progress.preparation, prep.nextQuestion(for: progress) == nil,
              let person = state.formPeople?.first(where: { $0.id == prep.applicantID }) else { return }
        let ids = prep.formIDs(for: progress)
        guard !ids.isEmpty else { return }
        let forms = try PrototypeForm.load()
        for id in ids {
            let key = id + ":" + person.id.uuidString
            guard state.formDrafts?[key] == nil else { continue }
            guard let form = forms.first(where: { $0.id == id }) else { throw SoviError.missingRecord }
            if state.formDrafts == nil { state.formDrafts = [:] }
            state.formDrafts?[key] = form.prefilledDraft(for: person, caseProgress: progress)
        }
    }

    private func commit(_ proposed: AppState) throws {
        var updated = proposed
        if updated.conversation.count > state.conversation.count {
            // Imported receipts, path answers and live replies share one display order, even if the clock repeats.
            var previous = max(state.conversation.last?.date ?? .distantPast, state.latestOnlineTurnAt ?? .distantPast)
            for i in state.conversation.count..<updated.conversation.count {
                updated.conversation[i].date = max(updated.conversation[i].date, previous.addingTimeInterval(0.0001))
                previous = updated.conversation[i].date
            }
        }
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
