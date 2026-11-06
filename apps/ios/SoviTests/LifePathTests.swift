import XCTest
import SwiftData
import UIKit
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

    func testActionBubbleWordMatchesTheDayAndTaskState() throws {
        let store = try store()
        var day = try XCTUnwrap(store.state.pathDays.first { $0.id == store.state.currentPathDayID })
        XCTAssertEqual(day.actionBubbleTitle, String(localized: "Auswählen"))
        day.entries = [try XCTUnwrap(store.node(id: LifePathSeed.stableID("P217-3")))]
        XCTAssertEqual(day.actionBubbleTitle, String(localized: "Vorbereiten"))
        day.entries = [PathNode(kind: .information, title: "Versicherung")]
        XCTAssertEqual(day.actionBubbleTitle, String(localized: "Lesen"))
        day.entries = [PathNode(kind: .task, title: "Unterlagen ordnen")]
        XCTAssertEqual(day.actionBubbleTitle, String(localized: "Starten"))
        day.entries[0].taskStatus = .inProgress
        XCTAssertEqual(day.actionBubbleTitle, String(localized: "Fortsetzen"))
        day.entries[0].taskStatus = .completed
        XCTAssertEqual(day.actionBubbleTitle, String(localized: "Ansehen"))
    }

    func testHaloKeepsIndependentOutcomesForEntriesOnOneDay() {
        var information = PathNode(kind: .information, title: "Unterlagen")
        var task = PathNode(kind: .task, title: "Rückruf")
        let state = AppState()
        XCTAssertEqual([information, task].map { $0.haloProgress(in: state, now: now) }, [.neutral, .pending])
        information.informationRead = true
        XCTAssertEqual([information, task].map { $0.haloProgress(in: state, now: now) }, [.done, .pending])
        task.taskStatus = .completed
        XCTAssertEqual([information, task].map { $0.haloProgress(in: state, now: now) }, [.done, .done])
    }

    func testExplicitOutcomesPersistAndUnknownPastItemsStayPending() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let store = try SoviStore(container: container, clock: { self.now })
        let appointmentNode = try XCTUnwrap(store.node(id: LifePathSeed.stableID("P217-1")))
        let appointmentID = try XCTUnwrap(appointmentNode.appointmentID)
        let original = try XCTUnwrap(store.state.appointments.first { $0.id == appointmentID })
        let afterVisit = original.date.addingTimeInterval(3600)
        XCTAssertEqual(appointmentNode.progress(in: store.state, now: afterVisit), .pending)
        XCTAssertEqual(store.state.appointments.first { $0.id == appointmentID }?.attendance, .unrecorded)
        try store.perform(.recordAttendance(appointmentID, .notAttended))
        XCTAssertEqual(appointmentNode.progress(in: store.state, now: now), .pending)
        XCTAssertEqual(appointmentNode.progress(in: store.state, now: afterVisit), .missed)
        XCTAssertEqual(store.state.appointments.first { $0.id == appointmentID }?.status, original.status)
        XCTAssertEqual(store.state.appointments.first { $0.id == appointmentID }?.provenance, original.provenance)
        try store.perform(.recordAttendance(appointmentID, .attended))
        XCTAssertEqual(appointmentNode.progress(in: store.state, now: afterVisit), .done)
        try store.perform(.recordAttendance(appointmentID, .unrecorded))
        XCTAssertEqual(appointmentNode.progress(in: store.state, now: afterVisit), .pending)
        let future = try XCTUnwrap(store.node(id: LifePathSeed.stableID("P218-1"))?.appointmentID)
        XCTAssertThrowsError(try store.perform(.recordAttendance(future, .attended)))
        XCTAssertThrowsError(try store.perform(.recordAttendance(future, .notAttended)))
        let taskID = LifePathSeed.stableID("P217-3")
        let tomorrow = now.addingTimeInterval(86400)
        XCTAssertEqual(store.node(id: taskID)?.progress(in: store.state, now: tomorrow), .pending)
        try store.perform(.setTask(taskID, .notDone))
        XCTAssertEqual(store.node(id: taskID)?.progress(in: store.state, now: now), .pending)
        XCTAssertEqual(store.node(id: taskID)?.progress(in: store.state, now: tomorrow), .missed)
        XCTAssertEqual(store.node(id: LifePathSeed.stableID("P220-1"))?.taskStatus, .notDone)
        let reopened = try SoviStore(container: container, clock: { self.now })
        XCTAssertEqual(reopened.node(id: taskID)?.taskStatus, .notDone)
        try reopened.perform(.setTask(taskID, .completed))
        XCTAssertEqual(reopened.node(id: taskID)?.progress(in: reopened.state, now: tomorrow), .done)
        try reopened.perform(.setTask(taskID, .open))
        XCTAssertEqual(reopened.node(id: taskID)?.progress(in: reopened.state, now: tomorrow), .pending)
    }

    func testGroupedProgressPrioritizesExplicitMissedThenIncompleteOutcomes() throws {
        let store = try store()
        let day = try XCTUnwrap(store.state.pathDays.first { $0.id == store.state.currentPathDayID })
        let later = now.addingTimeInterval(86400)
        XCTAssertEqual(day.progress(in: store.state, now: later), .pending)
        let appointmentID = try XCTUnwrap(day.entries.first { $0.appointmentID != nil }?.appointmentID)
        try store.perform(.recordAttendance(appointmentID, .notAttended))
        XCTAssertEqual(day.progress(in: store.state, now: later), .missed)
        try store.perform(.recordAttendance(appointmentID, .attended))
        XCTAssertEqual(day.progress(in: store.state, now: later), .pending)
        for entry in day.entries where entry.kind == .task { try store.perform(.setTask(entry.id, .completed)) }
        let completed = try XCTUnwrap(store.state.pathDays.first { $0.id == day.id })
        XCTAssertEqual(completed.progress(in: store.state, now: later), .done)
    }

    func testLocalProgressButtonsDoNotCaptureMedicalOrBookingRequests() throws {
        let store = try store(), before = store.state
        for text in ["Meine Termine", "Was steht als Nächstes an?", "What’s next?", "My appointments"] {
            let reply = try XCTUnwrap(DemoCompanionService.progressResponse(to: text, context: nil, state: store.state, now: now))
            XCTAssertEqual(reply.entryIDs.count, 3)
        }
        let report = try XCTUnwrap(DemoCompanionService.progressResponse(to: "I missed my appointment", context: nil, state: store.state, now: now))
        XCTAssertNil(report.attendanceQuestionID)
        XCTAssertTrue(report.entryIDs.isEmpty)
        for text in ["Ich möchte einen Arzttermin", "I want a doctor's appointment", "What's going on with my shoulder?", "My shoulder hurts", "Was steht in meinem Befund?"] {
            XCTAssertNil(DemoCompanionService.progressResponse(to: text, context: nil, state: store.state, now: now))
        }
        XCTAssertEqual(store.state, before)
    }

    func testCompactPathKeepsMilestonesOpenStepsAndPersonalAdditions() throws {
        let store = try store()
        let compact = store.state.compactPathDays
        XCTAssertEqual(compact.count, 15)
        XCTAssertEqual(store.state.pathDays.count, 208)
        XCTAssertEqual(store.state.latestPathDayID, "day-2026-11-05")
        let visibleIDs = Set(compact.flatMap(\.entries).map(\.id))
        XCTAssertTrue(store.state.uniqueOpenTasks.allSatisfy { visibleIDs.contains($0.id) })
        XCTAssertEqual(compact.filter(\.isPlanned).count, 5)
        try store.perform(.addNode(kind: .event, title: "Persönliche Notiz", detail: "", date: nil, location: "", appointmentStatus: .requestDraft))
        let added = try XCTUnwrap(store.state.nodes.first { $0.title == "Persönliche Notiz" })
        XCTAssertTrue(store.state.compactPathDays.contains { $0.entries.contains { $0.id == added.id } })
        XCTAssertEqual(store.state.latestPathDayID, "entry-\(added.id.uuidString)")
        XCTAssertEqual(store.state.nodes.count, 306)
    }

    func testStatusBarShortcutForwardsSwiftUIScrollCallbacksAndRestoresDelegate() {
        final class Delegate: NSObject, UIScrollViewDelegate {
            var updates = 0
            func scrollViewDidScroll(_ scrollView: UIScrollView) { updates += 1 }
        }
        let scroll = UIScrollView(), original = Delegate()
        scroll.delegate = original
        var jumps = 0
        let bridge = PathStatusBarScroll.Coordinator { jumps += 1 }
        bridge.attach(scroll)
        scroll.delegate?.scrollViewDidScroll?(scroll)
        XCTAssertEqual(original.updates, 1)
        XCTAssertEqual(scroll.delegate?.scrollViewShouldScrollToTop?(scroll), false)
        XCTAssertEqual(jumps, 1)
        bridge.enabled = false; bridge.attach(scroll)
        XCTAssertFalse(scroll.scrollsToTop)
        bridge.detach()
        XCTAssertTrue(scroll.delegate === original)
        XCTAssertTrue(scroll.scrollsToTop)
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

    func testCheckInPicksTheLatestEligibleVisitAndOnlyAsksForThatVisit() throws {
        var state = AppState()
        func add(_ title: String, _ offset: TimeInterval, status: AppointmentStatus = .confirmed, attendance: Attendance = .unrecorded) -> PathNode {
            let record = AppointmentRecord(title: title, date: now.addingTimeInterval(offset), status: status, attendance: attendance)
            let node = PathNode(kind: .appointment, title: title, appointmentID: record.id, date: record.date)
            state.appointments.append(record)
            state.nodes.append(node)
            return node
        }
        let recent = add("Physiotherapie", -3600)
        let older = add("Augenuntersuchung", -86_400)
        let cancelled = add("Abgesagt", -120, status: .cancelled)
        let draft = add("Anfrage", -60, status: .requestDraft)
        let answeredYes = add("Erledigt", -30, attendance: .attended)
        let answeredNo = add("Verpasst", -20, attendance: .notAttended)
        let upcoming = add("Heute später", 60)
        let startingNow = add("Jetzt", 0)
        let before = state
        let prompt = PathCompanionPrompt.make(state: state, now: now)
        XCTAssertEqual(prompt.contextID, recent.id)
        XCTAssertTrue(prompt.text.contains(recent.displayTitle))
        let reportedVisit = try XCTUnwrap(DemoCompanionService.progressResponse(to: "I missed my appointment", context: nil,
                                                                                state: state, now: now, language: .en))
        XCTAssertEqual(reportedVisit.attendanceQuestionID, recent.id)
        for node in [recent, older] {
            let reply = DemoCompanionService.entryResponse(for: node, state: state, now: now, language: .en)
            XCTAssertEqual(reply.attendanceQuestionID, node.id)
            XCTAssertTrue(reply.text.contains(node.displayTitle))
            XCTAssertTrue(reply.text.contains("?"))
        }
        for node in [cancelled, draft, answeredYes, answeredNo, upcoming, startingNow] {
            XCTAssertNil(DemoCompanionService.entryResponse(for: node, state: state, now: now).attendanceQuestionID, node.title)
        }
        XCTAssertEqual(state, before)
    }

    func testCheckInAnswerPersistsOnceAndCannotUpdateADifferentVisit() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let afterVisit = now.addingTimeInterval(9 * 3600)
        let store = try SoviStore(container: container, clock: { afterVisit })
        let node = try XCTUnwrap(store.node(id: LifePathSeed.stableID("P217-1")))
        let appointmentID = try XCTUnwrap(node.appointmentID)
        let future = LifePathSeed.stableID("P218-1")
        try store.perform(.beginAttendanceCheckIn(nodeID: node.id, question: "Did you go to your appointment?"))
        let questionedState = store.state
        XCTAssertEqual(questionedState.conversation.last?.attendanceQuestionID, node.id)
        XCTAssertEqual(questionedState.appointments.first { $0.id == appointmentID }?.attendance, .unrecorded)
        XCTAssertThrowsError(try store.perform(.answerAttendanceCheckIn(nodeID: future, attendance: .attended, answer: "Yes", confirmation: "Saved")))
        XCTAssertEqual(store.state, questionedState)
        let reopened = try SoviStore(container: container, clock: { afterVisit })
        try reopened.perform(.answerAttendanceCheckIn(nodeID: node.id, attendance: .notAttended, answer: "I didn’t go", confirmation: "Saved"))
        let answered = reopened.state
        XCTAssertEqual(answered.conversation.map(\.text), ["Did you go to your appointment?", "I didn’t go", "Saved"])
        XCTAssertEqual(answered.appointments.first { $0.id == appointmentID }?.attendance, .notAttended)
        XCTAssertEqual(node.progress(in: answered, now: afterVisit), .missed)
        XCTAssertNotEqual(PathCompanionPrompt.make(state: answered, now: afterVisit).contextID, node.id)
        _ = try? reopened.perform(.answerAttendanceCheckIn(nodeID: node.id, attendance: .attended, answer: "Yes", confirmation: "Saved"))
        XCTAssertEqual(reopened.state, answered)
        XCTAssertEqual(try SoviStore(container: container, clock: { afterVisit }).state, answered)
    }

    func testTypedCheckInAnswersAcceptWholeRepliesAndLeaveOtherQuestionsAlone() {
        let nodeID = UUID()
        let samples: [(String, Attendance?)] = [("I went", .attended), ("Nein", .notAttended), ("I didn’t go", .notAttended),
                                              ("Later", nil), ("evet", .attended), ("لا", .notAttended)]
        for (message, expected) in samples {
            guard case .answerCheckIn(let id, let attendance) = DemoCompanionService.checkInAnswer(to: message, nodeID: nodeID) else {
                XCTFail("Missing answer for \(message)")
                continue
            }
            XCTAssertEqual(id, nodeID)
            XCTAssertEqual(attendance, expected)
        }
        for message in ["Yes?", "No pain today", "I went to a different doctor", "Kann ich den Termin verschieben?"] {
            XCTAssertNil(DemoCompanionService.checkInAnswer(to: message, nodeID: nodeID), message)
        }
    }

    func testCheckInLaterKeepsAttendanceOpenUntilTheNextLocalDay() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let evening = now.addingTimeInterval(13 * 3600)
        let store = try SoviStore(container: container, clock: { evening })
        let node = try XCTUnwrap(store.node(id: LifePathSeed.stableID("P217-1")))
        try store.perform(.beginAttendanceCheckIn(nodeID: node.id, question: "Did you go?"))
        try store.perform(.answerAttendanceCheckIn(nodeID: node.id, attendance: nil, answer: "Later", confirmation: "Okay"))
        let reopened = try SoviStore(container: container, clock: { evening })
        let state = reopened.state
        let record = try XCTUnwrap(state.appointments.first { $0.id == node.appointmentID })
        let midnight = try XCTUnwrap(state.pathCalendar.dateInterval(of: .day, for: evening)?.end)
        XCTAssertEqual(record.attendance, .unrecorded)
        XCTAssertEqual(node.progress(in: state, now: evening), .pending)
        XCTAssertEqual(record.checkInDeferredUntil, midnight)
        XCTAssertNotEqual(PathCompanionPrompt.make(state: state, now: midnight.addingTimeInterval(-1)).contextID, node.id)
        XCTAssertEqual(PathCompanionPrompt.make(state: state, now: midnight).contextID, node.id)
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
