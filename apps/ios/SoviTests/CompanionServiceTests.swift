import XCTest
import SwiftData
@testable import Sovi

@MainActor
final class CompanionServiceTests: XCTestCase {
    private let service = DemoCompanionService()
    private var now: Date { ISO8601DateFormatter().date(from: "2026-11-05T11:00:00Z")! }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return value
    }

    private func store() throws -> SoviStore {
        try SoviStore(container: SoviStore.makeContainer(inMemory: true), clock: { self.now }, calendar: calendar)
    }

    private func importApprovedA(_ store: SoviStore) throws {
        let document = try store.fixture("A")
        for proposal in document.proposals {
            try store.perform(.approveProposal(documentID: document.id, proposalID: proposal.id, revision: proposal.revision, editedTitle: nil))
        }
    }

    func testSummaryReadsTaskAppointmentAndMedicationRecordsAfterCommands() throws {
        let store = try store()
        try importApprovedA(store)
        let initial = service.respond(to: "Was steht heute an?", context: nil, state: store.state, now: now)
        XCTAssertTrue(initial.text.contains("Offene Aufgaben: 6"))
        XCTAssertTrue(initial.text.contains("Termine: 5"))
        XCTAssertTrue(initial.text.contains("Einnahmen offen: 6"))

        let task = try XCTUnwrap(store.state.uniqueOpenTasks.first)
        try store.perform(.setTask(task.id, .completed))
        let schedule = try XCTUnwrap(store.state.schedules.first)
        let occurrence = try XCTUnwrap(schedule.occurrences.first)
        try store.perform(.recordMedication(scheduleID: schedule.id, occurrenceID: occurrence.id, log: .taken))
        var appointment = try XCTUnwrap(store.state.appointments.first)
        appointment.status = .cancelled
        try store.perform(.editAppointment(appointment))

        let stored = store.state
        let updated = service.respond(to: "Was ist noch offen?", context: nil, state: store.state, now: now)
        XCTAssertTrue(updated.text.contains("Offene Aufgaben: 5"))
        XCTAssertTrue(updated.text.contains("Termine: 4"))
        XCTAssertTrue(updated.text.contains("Einnahmen offen: 5"))
        XCTAssertEqual(store.state, stored)
    }

    func testAmbiguousCompletionAsksForItemAndNeverMutatesAnything() throws {
        let store = try store()
        try importApprovedA(store)
        let original = store.state
        for phrase in ["Ich habe das erledigt.", "Bin fertig.", "Das ist abgeschlossen."] {
            let response = service.respond(to: phrase, context: nil, state: store.state, now: now)
            XCTAssertTrue(response.text.contains("Welche Aufgabe"), phrase)
            XCTAssertNil(response.action, phrase)
            XCTAssertEqual(store.state, original)
        }
    }

    func testContextualCompletionOnlyProposesReview() throws {
        let store = try store()
        let task = try XCTUnwrap(store.state.uniqueOpenTasks.first)
        let original = store.state
        let response = service.respond(to: "Ich habe das erledigt.", context: task.id, state: store.state, now: now)
        guard case .preview(let id) = response.action else {
            return XCTFail("Completion must offer an explicit review, not apply a command")
        }
        XCTAssertEqual(id, task.id)
        XCTAssertTrue(response.text.contains(task.title))
        XCTAssertEqual(store.state, original)
        XCTAssertEqual(store.node(id: task.id)?.taskStatus, .open)
    }

    func testRequiredIntentShortcutsReturnReviewableActions() throws {
        let state = try store().state
        let docs = service.respond(to: "Ich habe einen Entlassungsbrief.", context: nil, state: state, now: now)
        guard case .documents = docs.action else { return XCTFail("Missing document selection action") }
        let draft = service.respond(to: "Hilf mir mit dem Antrag.", context: nil, state: state, now: now)
        guard case .draft = draft.action else { return XCTFail("Missing editable draft action") }
        let appointment = service.respond(to: "Ich möchte einen Termin eintragen.", context: nil, state: state, now: now)
        guard case .add(.appointment) = appointment.action else { return XCTFail("Missing appointment editor action") }
        let event = service.respond(to: "Ich möchte ein Ereignis hinzufügen.", context: nil, state: state, now: now)
        guard case .add(.event) = event.action else { return XCTFail("Missing event editor action") }
        let privacy = service.respond(to: "Was hast du gespeichert?", context: nil, state: state, now: now)
        guard case .controls = privacy.action else { return XCTFail("Missing direct local-data controls action") }
    }

    func testEvidenceComesFromSelectedStoredRecord() throws {
        let store = try store()
        try importApprovedA(store)
        let node = try XCTUnwrap(store.nodes.first { $0.proposalID != nil })
        let response = service.respond(to: "Warum steht das auf meinem Weg?", context: node.id, state: store.state, now: now)
        XCTAssertEqual(response.evidence, node.evidence)
        XCTAssertTrue(response.evidence.allSatisfy { reference in
            store.document(id: reference.documentID)?.text.contains(reference.quote) == true
        })
        guard case .preview(let id) = response.action else { return XCTFail("Expected source-bearing preview") }
        XCTAssertEqual(id, node.id)
        let ambiguous = service.respond(to: "Warum steht das auf meinem Weg?", context: nil, state: store.state, now: now)
        XCTAssertTrue(ambiguous.evidence.isEmpty)
        XCTAssertNil(ambiguous.action)
    }

    func testPrivacySummaryReflectsDeletionAndCurrentRecords() throws {
        let store = try store()
        try importApprovedA(store)
        try store.perform(.appendConversation(role: "user", text: "Eine Frage"))
        let saved = service.respond(to: "Was hast du gespeichert?", context: nil, state: store.state, now: now)
        XCTAssertTrue(saved.text.contains("\(store.state.nodes.count) Einträge"))
        XCTAssertTrue(saved.text.contains("\(store.state.documents.count) Dokumente"))
        XCTAssertTrue(saved.text.contains("1 Nachrichten"))
        try store.perform(.deleteLocalData)
        let empty = service.respond(to: "Was hast du gespeichert?", context: nil, state: store.state, now: now)
        XCTAssertTrue(empty.text.contains("0 Einträge, 0 Dokumente und 0 Nachrichten"))
    }

    func testGermanCompletionVariantWithTaskWordStillRequiresReview() throws {
        let store = try store()
        let task = try XCTUnwrap(store.state.uniqueOpenTasks.first)
        let response = service.respond(to: "Ich habe die Aufgabe erledigt.", context: task.id, state: store.state, now: now)
        guard case .preview(let id) = response.action else {
            return XCTFail("Completed task wording must not create a new task")
        }
        XCTAssertEqual(id, task.id)
        XCTAssertEqual(store.node(id: task.id)?.taskStatus, .open)
    }

    func testGermanSummaryVariantWithTaskWordUsesCurrentState() throws {
        let store = try store()
        let response = service.respond(to: "Welche Aufgaben sind noch offen?", context: nil, state: store.state, now: now)
        XCTAssertTrue(response.text.contains("Offene Aufgaben: 4"))
        if case .add = response.action { XCTFail("A question about open tasks must not create a task") }
    }

    func testExplicitAppointmentEntryIntentWorksWithTodayInSentence() throws {
        let store = try store()
        let response = service.respond(to: "Ich möchte heute einen Termin eintragen.", context: nil, state: store.state, now: now)
        guard case .add(.appointment) = response.action else {
            return XCTFail("Explicit appointment-entry intent should open a reviewable editor")
        }
    }

    func testUnsupportedRequestHasNoSideEffectsOrInventedAction() throws {
        let store = try store()
        let original = store.state
        let response = service.respond(to: "Löse ein Kreuzworträtsel für mich.", context: nil, state: store.state, now: now)
        XCTAssertTrue(response.text.contains("Aufgaben, Termine oder Unterlagen?"))
        XCTAssertNil(response.action)
        XCTAssertEqual(store.state, original)
    }
}
