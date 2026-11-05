import XCTest
import SwiftData
@testable import Sovi

@MainActor
final class LifePathTests: XCTestCase {
    private var now: Date { ISO8601DateFormatter().date(from: "2026-11-05T08:00:00Z")! }
    private func store() throws -> SoviStore {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return try SoviStore(container: SoviStore.makeContainer(inMemory: true), clock: { self.now }, calendar: calendar)
    }

    func testAllSourceEntriesGroupIntoExactDailyButtonsAndHalos() throws {
        let state = try store().state
        XCTAssertEqual(state.nodes.count, 305)
        XCTAssertEqual(state.pathDays.count, 208)
        XCTAssertEqual(state.pathDays.filter { $0.haloSegmentCount > 0 }.count, 67)
        XCTAssertEqual(state.pathDays.filter(\.isPlanned).count, 5)
        XCTAssertEqual(state.pathDays.reduce(0) { $0 + $1.entryCount }, 305)
        XCTAssertEqual(Set(state.nodes.map(\.id)).count, 305)
        XCTAssertEqual(state.currentPathDayID, "day-2026-11-05")
    }

    func testOpeningGroupedRecordsAndSourcesDoesNotChangeAnyStatus() throws {
        let store = try store(); let before = store.state
        let today = try XCTUnwrap(store.state.pathDays.first { $0.id == store.state.currentPathDayID })
        XCTAssertEqual(today.title, "Mein Tag"); XCTAssertEqual(today.entries.count, 3)
        for node in today.entries {
            _ = store.node(id: node.id)
            for reference in node.evidence {
                let original = try XCTUnwrap(store.document(id: reference.documentID))
                XCTAssertTrue(original.text.contains(reference.quote))
            }
        }
        XCTAssertEqual(store.state, before)
    }

    func testQuestionnaireReferencesShareOneTaskAndDraftWithoutChangingHaloCounts() throws {
        let store = try store()
        XCTAssertEqual(store.state.uniqueOpenTasks.count, 4)
        let canonical = LifePathSeed.stableID("P217-3")
        let reminder = LifePathSeed.stableID("P220-1")
        XCTAssertEqual(store.node(id: reminder)?.history?.linkedTaskID, canonical)
        try store.perform(.saveLifeDraft(.questionnaire, "Unbekannte Angaben bleiben offen"))
        try store.perform(.setTask(reminder, .completed))
        XCTAssertEqual(store.node(id: canonical)?.taskStatus, .completed)
        XCTAssertEqual(store.node(id: reminder)?.taskStatus, .completed)
        XCTAssertEqual(store.state.uniqueOpenTasks.count, 3)
        XCTAssertEqual(store.state.lifeDrafts?[LifeDraftKind.questionnaire.rawValue], "Unbekannte Angaben bleiben offen")
        XCTAssertEqual(store.state.pathDays.first { $0.id == "day-2026-11-05" }?.haloSegmentCount, 3)
        XCTAssertEqual(store.state.pathDays.first { $0.id == "day-2026-11-23" }?.haloSegmentCount, 3)
    }

    func testHistoricalMedicationDoesNotCreateScheduleAndTherapyIsNotInferred() throws {
        let state = try store().state
        XCTAssertTrue(state.schedules.isEmpty)
        XCTAssertFalse(state.notificationsEnabled)
        XCTAssertEqual(state.documentedTherapySessions, 4)
        XCTAssertEqual(state.appointments.count, 5)
        XCTAssertTrue(state.appointments.allSatisfy { $0.status == .confirmed && $0.attendance == .unrecorded })
        XCTAssertTrue(state.nodes.contains { $0.history?.category == .medicationEvidence })
        XCTAssertEqual(state.nodes.filter { $0.vaccination != nil }.count, 9)
    }

    func testAppointmentEditMovesOnlyItsEntryAndAttendanceRequiresExplicitRecord() throws {
        let store = try store()
        let node = try XCTUnwrap(store.node(id: LifePathSeed.stableID("P217-1")))
        var appointment = try XCTUnwrap(store.state.appointments.first { $0.id == node.appointmentID })
        appointment.date = now.addingTimeInterval(2 * 86_400)
        try store.perform(.editAppointment(appointment))
        XCTAssertEqual(store.state.pathDays.first { $0.id == "day-2026-11-05" }?.entryCount, 2)
        XCTAssertEqual(store.state.pathDays.first { $0.id == "day-2026-11-07" }?.entryCount, 1)
        XCTAssertEqual(store.state.documentedTherapySessions, 4)
        appointment.attendance = .attended
        try store.perform(.editAppointment(appointment))
        XCTAssertEqual(store.state.documentedTherapySessions, 5)
        XCTAssertEqual(store.state.nodes.count, 305)
    }

    func testScenarioRoundTripDeletionAndReloadKeepTheirDistinctMeanings() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let first = try SoviStore(container: container, clock: { self.now })
        try first.perform(.saveLifeDraft(.questionnaire, "Entwurf"))
        let second = try SoviStore(container: container, clock: { self.now.addingTimeInterval(90 * 86_400) })
        XCTAssertEqual(second.state, first.state)
        try second.perform(.deleteLocalData)
        let empty = try SoviStore(container: container)
        XCTAssertTrue(empty.state.pathDays.isEmpty)
        XCTAssertNil(empty.state.lifeScenario)
        XCTAssertNil(empty.state.lifeDrafts)
        try empty.perform(.reloadDemo)
        XCTAssertEqual(empty.state.pathDays.count, 208)
        XCTAssertEqual(empty.state.documentedTherapySessions, 4)
    }
    func testExistingSnapshotWithoutScenarioFieldsIsPreservedUntilExplicitReload() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        var previous = AppState(seededAt: now, nodes: [PathNode(kind: .task, title: "Mein bestehender Schritt")])
        previous.composerDraft = "Unfertige Nachricht"
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as! [String: Any]
        json.removeValue(forKey: "lifeScenario"); json.removeValue(forKey: "lifeDrafts")
        context.insert(SoviSnapshot(payload: try JSONSerialization.data(withJSONObject: json)))
        try context.save()
        let restored = try SoviStore(container: container, clock: { self.now })
        XCTAssertNil(restored.state.lifeScenario)
        XCTAssertEqual(restored.nodes.count, 1)
        XCTAssertEqual(restored.nodes[0].title, "Mein bestehender Schritt")
        XCTAssertEqual(restored.state.composerDraft, "Unfertige Nachricht")
        try restored.perform(.reloadDemo)
        XCTAssertEqual(restored.state.pathDays.count, 208)
    }

    func testReimportingTheOriginalTextDoesNotDuplicateHistoryOrDocuments() throws {
        let store = try store()
        let original = try XCTUnwrap(store.state.documents.first)
        let imported = try store.importText(original.text, title: "Erneut digitalisiert.txt")
        XCTAssertEqual(imported.id, original.id)
        XCTAssertEqual(store.state.documents.count, 2)
        XCTAssertEqual(store.state.pathDays.count, 208)
        XCTAssertEqual(store.state.nodes.count, 305)
    }

    func testPathBubbleUsesStoredAppointmentWithoutChangingFacts() throws {
        let store = try store(); let before = store.state
        let prompt = PathCompanionPrompt.make(state: store.state, now: now)
        XCTAssertEqual(prompt.contextID, LifePathSeed.stableID("P217-1"))
        XCTAssertTrue(prompt.text.contains("16:00"))
        XCTAssertEqual(store.state, before)
    }

    func testBubbleThirtyDayWindowAndAppointmentEligibility() {
        var state = AppState()
        let end = state.pathCalendar.date(byAdding: .day, value: 30, to: now)!
        let appointment = AppointmentRecord(title: "Termin", date: end, status: .confirmed)
        let node = PathNode(kind: .appointment, title: "Termin", appointmentID: appointment.id)
        state.nodes = [node]; state.appointments = [appointment]
        XCTAssertEqual(PathCompanionPrompt.make(state: state, now: now).contextID, node.id)
        state.appointments[0].date = end.addingTimeInterval(1)
        XCTAssertNil(PathCompanionPrompt.make(state: state, now: now).contextID)
        state.appointments[0].date = now.addingTimeInterval(3600)
        for status in [AppointmentStatus.cancelled, .requestDraft] {
            state.appointments[0].status = status
            XCTAssertNil(PathCompanionPrompt.make(state: state, now: now).contextID)
        }
        state.appointments[0].status = .confirmed
        state.appointments[0].attendance = .attended
        XCTAssertNil(PathCompanionPrompt.make(state: state, now: now).contextID)
    }

    func testQuietCheckInAndDateOnlyTasksDoNotReuseOldContext() {
        var state = AppState(focusContextID: UUID())
        XCTAssertNil(PathCompanionPrompt.make(state: state, now: now).contextID)
        let day = state.pathCalendar.startOfDay(for: now)
        let task = PathNode(kind: .task, title: "Unterlagen", date: day)
        state.nodes = [task]
        XCTAssertEqual(PathCompanionPrompt.make(state: state, now: now).contextID, task.id)
        state.nodes[0].taskStatus = .completed
        XCTAssertNil(PathCompanionPrompt.make(state: state, now: now).contextID)
        state.nodes[0].taskStatus = .open
        state.nodes[0].date = day.addingTimeInterval(-86_400)
        XCTAssertNil(PathCompanionPrompt.make(state: state, now: now).contextID)
        state.nodes[0].date = nil
        XCTAssertNil(PathCompanionPrompt.make(state: state, now: now).contextID)
    }

    func testVaccinationsUseOriginalDatesFieldsAndSourcePages() throws {
        let store = try store()
        let vaccinations = store.nodes.filter { $0.vaccination != nil }
        XCTAssertEqual(vaccinations.count, 9)
        XCTAssertEqual(vaccinations.filter { $0.vaccination?.disease == "COVID-19" }.count, 5)
        XCTAssertEqual(vaccinations.filter { $0.vaccination?.disease == "Influenza" }.count, 4)
        let day = try XCTUnwrap(store.state.pathDays.first { $0.id == "day-2025-11-03" })
        XCTAssertEqual(day.title, "Impfungen"); XCTAssertEqual(day.haloSegmentCount, 2)
        let covid = try XCTUnwrap(vaccinations.first { $0.vaccination?.batch == "MT0705" })
        XCTAssertEqual(covid.vaccination?.product, "COMIRNATY LP.8.1 INJ30 10x6")
        XCTAssertFalse(try XCTUnwrap(covid.vaccination).hasDocumentedTime)
        XCTAssertTrue(try XCTUnwrap(covid.vaccination).recordedAtText.contains("14:02"))
        let secondPage = try XCTUnwrap(vaccinations.first { $0.vaccination?.batch == "V3H731V" })
        XCTAssertEqual(secondPage.evidence.first?.pageNumber, 2)
        for node in vaccinations {
            let reference = try XCTUnwrap(node.evidence.first)
            let document = try XCTUnwrap(store.document(id: reference.documentID))
            XCTAssertEqual(document.bundledPDFName, VaccinationPassSeed.resourceName)
            XCTAssertTrue(document.text.contains(reference.quote))
        }
    }

    func testExistingDemoGetsVaccinationsOnceWithoutLosingProgress() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        var original = try LifePathSeed.state(now: now, calendar: .current, includingVaccinationPass: false)
        let taskID = LifePathSeed.stableID("P217-2")
        let task = try XCTUnwrap(original.nodes.firstIndex { $0.id == taskID })
        original.nodes[task].taskStatus = .completed
        original.lifeDrafts = ["questionnaire": "Bestehende Notizen"]
        original.composerDraft = "Unfertig"
        let custom = PathNode(kind: .task, title: "Mein eigener Schritt")
        original.nodes.append(custom)
        let context = ModelContext(container)
        context.insert(SoviSnapshot(payload: try JSONEncoder().encode(original)))
        try context.save()
        let migrated = try SoviStore(container: container, clock: { self.now })
        XCTAssertEqual(migrated.state.vaccinationPassVersion, 1)
        XCTAssertEqual(migrated.nodes.filter { $0.vaccination != nil }.count, 9)
        XCTAssertFalse(migrated.nodes.contains { $0.history?.category == .vaccination })
        XCTAssertEqual(migrated.node(id: taskID)?.taskStatus, .completed)
        XCTAssertTrue(migrated.nodes.contains(custom))
        XCTAssertEqual(migrated.state.lifeDrafts, original.lifeDrafts)
        XCTAssertEqual(migrated.state.composerDraft, original.composerDraft)
        XCTAssertEqual(migrated.state.lifeScenario, original.lifeScenario)
        let reopened = try SoviStore(container: container, clock: { self.now })
        XCTAssertEqual(reopened.state, migrated.state)
    }

    func testVaccinationSourceReimportDoesNotDuplicateRecordsOrCreatePlans() throws {
        let store = try store()
        let source = try XCTUnwrap(store.state.documents.first { $0.bundledPDFName != nil })
        let imported = try store.importText(source.text.replacingOccurrences(of: "\n", with: "\0\n"), title: "Impfpass.pdf")
        XCTAssertEqual(imported.id, source.id)
        XCTAssertEqual(store.state.documents.count, 2)
        XCTAssertEqual(store.state.nodes.count, 305)
        XCTAssertEqual(store.state.appointments.count, 5)
        XCTAssertEqual(store.state.uniqueOpenTasks.count, 4)
        XCTAssertTrue(store.state.schedules.isEmpty)
    }

}
