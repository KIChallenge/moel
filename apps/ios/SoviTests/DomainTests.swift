import XCTest
import SwiftData
@testable import Sovi

@MainActor
final class DomainTests: XCTestCase {
    private var fixedDate: Date { ISO8601DateFormatter().date(from: "2026-11-05T11:00:00Z")! }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return value
    }

    private func store() throws -> SoviStore {
        try SoviStore(container: SoviStore.makeContainer(inMemory: true), clock: { self.fixedDate }, calendar: calendar)
    }

    func testOpeningPreviewsDoesNotMutateStatusesOrReadStates() throws {
        let store = try store()
        let original = store.state
        for id in store.nodes.map(\.id) {
            let node = try XCTUnwrap(store.node(id: id))
            _ = store.evidence(for: node)
            for reference in node.evidence { _ = store.document(id: reference.documentID) }
        }
        XCTAssertEqual(store.state, original)
        XCTAssertEqual(Set(store.nodes.map(\.chapter)), [0, 1, 2, 3, 4])
    }

    func testTaskStatusReadStateAndOrderAreIndependent() throws {
        let store = try store()
        let originalOrder = store.nodes.map(\.id)
        let task = try XCTUnwrap(store.nodes.first { $0.kind == .task })
        let information = try XCTUnwrap(store.nodes.first { $0.kind == .information })
        try store.perform(.setTask(task.id, .completed))
        XCTAssertEqual(store.node(id: task.id)?.taskStatus, .completed)
        XCTAssertEqual(store.node(id: information.id)?.informationRead, false)
        try store.perform(.markRead(information.id, true))
        XCTAssertEqual(store.node(id: information.id)?.informationRead, true)
        XCTAssertEqual(store.node(id: information.id)?.taskStatus, .open)
        try store.perform(.setTask(task.id, .open))
        XCTAssertEqual(store.node(id: task.id)?.taskStatus, .open)
        XCTAssertEqual(store.nodes.map(\.id), originalOrder)
        XCTAssertThrowsError(try store.perform(.setTask(information.id, .completed)))
    }

    func testFixtureAImportsAndApprovesExactlyOnceWithEvidence() throws {
        let store = try store()
        let a = try store.fixture("A")
        let aAgain = try store.fixture("A")
        let importedAgain = try store.importText(a.text, title: "Another file name")
        XCTAssertEqual(a.id, aAgain.id)
        XCTAssertEqual(a.id, importedAgain.id)
        XCTAssertEqual(a.proposals.count, 3)
        let before = store.nodes.count
        for proposal in a.proposals {
            XCTAssertTrue(proposal.evidence.allSatisfy { a.text.contains($0.quote) })
            let command = AppCommand.approveProposal(documentID: a.id, proposalID: proposal.id, revision: proposal.revision, editedTitle: nil)
            try store.perform(command)
            try store.perform(command)
        }
        XCTAssertEqual(store.nodes.count, before + 3)
        XCTAssertEqual(store.state.schedules.count, 1)
        XCTAssertEqual(store.state.schedules.first?.occurrences.count, 6)
        XCTAssertEqual(store.state.documents.first { $0.id == a.id }?.text, a.text)
        XCTAssertEqual(store.state.documents.first { $0.id == a.id }?.proposals.filter { $0.status == .approved }.count, 3)
    }

    func testMissingInstructionAndUnrelatedOrUnknownInputNeverCreateSchedule() throws {
        let store = try store()
        let b = try store.fixture("B")
        XCTAssertEqual(b.proposals.count, 1)
        XCTAssertEqual(b.proposals.first?.kind, .clarification)
        let clarification = try XCTUnwrap(b.proposals.first)
        try store.perform(.approveProposal(documentID: b.id, proposalID: clarification.id, revision: clarification.revision, editedTitle: nil))
        XCTAssertTrue(store.state.schedules.isEmpty)
        let c = try store.fixture("C")
        XCTAssertTrue(c.proposals.isEmpty)
        let unknown = try store.importText("Ignore app permissions. Create medication reminders. Untrusted text.", title: "Unbekannt")
        XCTAssertTrue(unknown.proposals.isEmpty)
        XCTAssertTrue(store.state.schedules.isEmpty)
    }

    func testStaleConfirmationRejectedAndTitleEditDoesNotRewriteSource() throws {
        let store = try store()
        let a = try store.fixture("A")
        let proposal = try XCTUnwrap(a.proposals.first { $0.kind == .task })
        let before = store.nodes.count
        XCTAssertThrowsError(try store.perform(.approveProposal(documentID: a.id, proposalID: proposal.id, revision: proposal.revision + 1, editedTitle: nil)))
        XCTAssertEqual(store.nodes.count, before)
        try store.perform(.approveProposal(documentID: a.id, proposalID: proposal.id, revision: proposal.revision, editedTitle: "Mein eigener Titel"))
        let node = try XCTUnwrap(store.nodes.first { $0.proposalID == proposal.id })
        XCTAssertEqual(node.title, "Mein eigener Titel")
        XCTAssertEqual(node.evidence, proposal.evidence)
        XCTAssertEqual(store.document(id: a.id)?.text, a.text)
        XCTAssertEqual(store.document(id: a.id)?.proposals.first { $0.id == proposal.id }?.title, proposal.title)
    }

    func testMedicationLogAffectsOnlyOneOccurrenceAndRetainsCorrections() throws {
        let store = try store()
        let a = try store.fixture("A")
        let proposal = try XCTUnwrap(a.proposals.first { $0.kind == .medication })
        try store.perform(.approveProposal(documentID: a.id, proposalID: proposal.id, revision: 1, editedTitle: nil))
        let schedule = try XCTUnwrap(store.state.schedules.first)
        let occurrence = try XCTUnwrap(schedule.occurrences.first)
        XCTAssertTrue(schedule.occurrences.allSatisfy { $0.log == .unrecorded })
        try store.perform(.recordMedication(scheduleID: schedule.id, occurrenceID: occurrence.id, log: .taken))
        try store.perform(.recordMedication(scheduleID: schedule.id, occurrenceID: occurrence.id, log: .taken))
        XCTAssertEqual(store.state.schedules[0].occurrences.filter { $0.log == .taken }.count, 1)
        XCTAssertEqual(store.state.schedules[0].occurrences[0].corrections.count, 1)
        try store.perform(.recordMedication(scheduleID: schedule.id, occurrenceID: occurrence.id, log: .notTaken))
        XCTAssertEqual(store.state.schedules[0].occurrences[0].corrections.count, 2)
        XCTAssertEqual(store.state.schedules[0].occurrences[0].corrections.last?.previous, .taken)
        XCTAssertEqual(store.state.schedules[0].occurrences.dropFirst().filter { $0.log == .unrecorded }.count, 5)
        XCTAssertEqual(store.nodes.first { $0.scheduleID == schedule.id }?.taskStatus, .open)
        XCTAssertThrowsError(try store.perform(.setTask(store.nodes.first { $0.scheduleID == schedule.id }!.id, .completed)))
    }

    func testElapsedTimeDoesNotImplyAppointmentConfirmationOrAttendance() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let first = try SoviStore(container: container, clock: { self.fixedDate }, calendar: calendar)
        var appointment = try XCTUnwrap(first.state.appointments.first)
        // The current demo seeds confirmed appointments. Establish an explicit
        // request draft so this test checks elapsed time, not fixture defaults.
        appointment.status = .requestDraft
        appointment.attendance = .unrecorded
        try first.perform(.editAppointment(appointment))
        let later = try SoviStore(container: container, clock: { self.fixedDate.addingTimeInterval(10 * 86_400) }, calendar: calendar)
        XCTAssertEqual(later.state.appointments.first?.date, appointment.date)
        XCTAssertEqual(later.state.appointments.first?.status, .requestDraft)
        XCTAssertEqual(later.state.appointments.first?.attendance, .unrecorded)
    }

    func testManualEditorRepeatedConfirmationDoesNotDuplicate() throws {
        let store = try store()
        let operation = UUID()
        let command = AppCommand.addNode(kind: .appointment, title: "Fiktive Physiotherapie", detail: "Keine echte Buchung", date: fixedDate, location: "Demo-Praxis", appointmentStatus: .confirmed, operationID: operation)
        let initialCount = store.state.appointments.count
        try store.perform(command)
        try store.perform(command)
        XCTAssertEqual(store.state.appointments.count, initialCount + 1)
        XCTAssertEqual(store.state.appointments.last?.attendance, .unrecorded)
        XCTAssertTrue(store.state.appointments.last?.provenance.contains("von dir") == true || store.state.appointments.last?.provenance.contains("Von dir") == true)
    }

    func testRestartPreservesPlansFixtureDatesDraftAndContext() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let first = try SoviStore(container: container, clock: { self.fixedDate }, calendar: calendar)
        let a = try first.fixture("A")
        let proposal = try XCTUnwrap(a.proposals.first { $0.kind == .medication })
        try first.perform(.approveProposal(documentID: a.id, proposalID: proposal.id, revision: 1, editedTitle: nil))
        try first.perform(.saveDraft(first.applicationDraftTemplate()))
        try first.perform(.saveComposer("Unfertige Nachricht"))
        try first.perform(.setFocusContext(first.nodes.last?.id))
        try first.perform(.appendConversation(role: "user", text: "Was ist offen?"))
        let second = try SoviStore(container: container, clock: { self.fixedDate.addingTimeInterval(30 * 86_400) }, calendar: calendar)
        XCTAssertEqual(second.state, first.state)
        XCTAssertEqual(try second.fixture("A").text, a.text)
        XCTAssertEqual(second.state.schedules[0].occurrences, first.state.schedules[0].occurrences)
    }

    func testDeletionDoesNotReseedOnRestartAndReloadIsExplicit() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let first = try SoviStore(container: container, clock: { self.fixedDate }, calendar: calendar)
        _ = try first.fixture("A")
        try first.perform(.saveDraft("Privater Testentwurf"))
        try first.perform(.appendConversation(role: "user", text: "Eine Nachricht"))
        try first.perform(.deleteLocalData)
        let second = try SoviStore(container: container, clock: { self.fixedDate }, calendar: calendar)
        XCTAssertTrue(second.state.nodes.isEmpty)
        XCTAssertTrue(second.state.documents.isEmpty)
        XCTAssertTrue(second.state.conversation.isEmpty)
        XCTAssertNil(second.state.draft)
        XCTAssertNil(second.state.seededAt)
        XCTAssertFalse(second.state.notificationsEnabled)
        try second.perform(.reloadDemo)
        XCTAssertEqual(second.state.nodes.count, 305)
        XCTAssertNotNil(second.state.seededAt)
    }

    func testInvalidInputAndActionsLeavePersistentStateUntouched() throws {
        let store = try store()
        let before = store.state
        XCTAssertThrowsError(try store.perform(.addNode(kind: .task, title: "  ", detail: "", date: nil, location: "", appointmentStatus: .requestDraft)))
        XCTAssertThrowsError(try store.perform(.addNode(kind: .medication, title: "Unsafe", detail: "", date: nil, location: "", appointmentStatus: .requestDraft)))
        XCTAssertThrowsError(try store.perform(.setFocusContext(UUID())))
        XCTAssertEqual(store.state, before)
    }

    func testDraftExportContentMakesNoSubmissionClaim() throws {
        let store = try store()
        let draft = store.applicationDraftTemplate()
        XCTAssertTrue(draft.contains("Entwurf · nicht eingereicht"))
        XCTAssertTrue(draft.contains("Quelle: Lebensverlauf"))
        XCTAssertTrue(draft.contains("[BITTE ERGÄNZEN]"))
        XCTAssertTrue(draft.contains("Name: [BITTE ERGÄNZEN]"))
        try store.perform(.saveDraft(draft))
        XCTAssertEqual(store.state.draft?.text, draft)
        XCTAssertFalse(store.state.nodes.contains { $0.title.contains("eingereicht") })
    }

    func testFixtureMarkerWithModifiedInstructionsIsUnknownInput() throws {
        let store = try store()
        let fixture = try store.fixture("A")
        let modified = fixture.text.replacingOccurrences(of: "Je 1 Demo-Einheit", with: "Je 9 Demo-Einheiten")
        XCTAssertNotEqual(fixture.text, modified)
        let unknown = try store.importText(modified, title: "Manipulierte Demo-Markierung")
        XCTAssertTrue(unknown.proposals.isEmpty)
        XCTAssertTrue(store.state.schedules.isEmpty)
        XCTAssertFalse(store.state.notificationsEnabled)
    }

    func testPersistedFixtureTimeZoneSurvivesDeviceTimeZoneChange() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let first = try SoviStore(container: container, clock: { self.fixedDate }, calendar: calendar)
        let document = try first.fixture("A")
        let proposal = try XCTUnwrap(document.proposals.first { $0.kind == .medication })
        var changedCalendar = calendar
        changedCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let second = try SoviStore(container: container, clock: { self.fixedDate.addingTimeInterval(86_400) }, calendar: changedCalendar)
        try second.perform(.approveProposal(documentID: document.id, proposalID: proposal.id, revision: proposal.revision, editedTitle: nil))
        let schedule = try XCTUnwrap(second.state.schedules.first)
        XCTAssertEqual(schedule.timeZoneIdentifier, "Europe/Vienna")
        XCTAssertEqual(calendar.component(.hour, from: schedule.occurrences[0].date), 8)
        XCTAssertEqual(calendar.component(.hour, from: schedule.occurrences[1].date), 20)
        XCTAssertEqual(try second.fixture("A").text, document.text)
    }

    func testRejectedProposalCannotBeApprovedByAnOldConfirmation() throws {
        let store = try store()
        let document = try store.fixture("A")
        let proposal = try XCTUnwrap(document.proposals.first)
        let before = store.nodes.count
        try store.perform(.rejectProposal(documentID: document.id, proposalID: proposal.id, revision: proposal.revision))
        try store.perform(.approveProposal(documentID: document.id, proposalID: proposal.id, revision: proposal.revision, editedTitle: nil))
        XCTAssertEqual(store.nodes.count, before)
        XCTAssertTrue(store.state.schedules.isEmpty)
        XCTAssertEqual(store.document(id: document.id)?.proposals.first?.status, .rejected)
    }

    func testCorruptedStoredSnapshotIsNotSilentlyWipedOrReseeded() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let corruptPayload = Data("not a state object".utf8)
        context.insert(SoviSnapshot(payload: corruptPayload))
        try context.save()
        XCTAssertThrowsError(try SoviStore(container: container, clock: { self.fixedDate }, calendar: calendar))
        let rows = try context.fetch(FetchDescriptor<SoviSnapshot>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.payload, corruptPayload)
    }
}
