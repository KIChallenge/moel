// Appended to the unchanged Foundation-only production sources by check-life-path.sh.
let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let fixtures = Bundle(url: bundleURL) else { fatalError("Fixture bundle unavailable") }
var testCalendar = Calendar(identifier: .gregorian)
testCalendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
let testDate = ISO8601DateFormatter().date(from: "2026-11-05T08:00:00Z")!
let seeded = try LifePathSeed.state(now: testDate, calendar: testCalendar, bundle: fixtures)
func verify(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    print("PASS: " + label)
}
verify(seeded.nodes.count == 305 && seeded.pathDays.count == 208, "305 entries project to 208 unique days")
verify(seeded.pathDays.filter { $0.haloSegmentCount > 0 }.count == 67, "67 multi-entry days have exact-count halos")
verify(seeded.pathDays.filter(\.isPlanned).count == 5, "Only the five source outlook days are marked planned")
verify(seeded.pathDays.first?.title == "Geburt" && seeded.pathDays.first?.entries.count == 3, "Birth day preserves three distinct records")
verify(seeded.pathDays.last?.entries.first?.title == "Befundgespräch", "Chronology ends at the planned results appointment")
let today = seeded.pathDays.first { $0.id == seeded.currentPathDayID }!
verify(today.id == "day-2026-11-05" && today.entries.count == 3 && today.title == "Mein Tag", "Current anchor is the three-entry day from 5 November")
verify(seeded.appointments.count == 5 && seeded.appointments.allSatisfy { $0.attendance == .unrecorded }, "Five explicit appointments, no implied attendance")
verify(seeded.schedules.isEmpty, "Historical medication evidence creates no schedules or alerts")
verify(seeded.documentedTherapySessions == 4, "Exactly four source-documented therapy attendances")
verify(seeded.uniqueOpenTasks.count == 4, "Questionnaire reminder does not duplicate its canonical task")
let reminder = seeded.nodes.first { $0.history?.dayID == "P220" && $0.history?.entryNumber == 1 }!
verify(reminder.history?.linkedTaskID == LifePathSeed.stableID("P217-3"), "Both questionnaire references point to one task")
verify(seeded.nodes.allSatisfy { node in node.evidence.allSatisfy { reference in seeded.documents.first(where: { $0.id == reference.documentID })?.text.contains(reference.quote) == true } }, "All 305 entries retain exact passages in their own source document")
let later = try LifePathSeed.state(now: testDate.addingTimeInterval(60*86_400), calendar: testCalendar, bundle: fixtures)
verify(later.nodes.map(\.id) == seeded.nodes.map(\.id) && later.nodes.map(\.date) == seeded.nodes.map(\.date), "Stable identities and scenario dates on later loads")
let data = try JSONEncoder().encode(seeded)
let decoded = try JSONDecoder().decode(AppState.self, from: data)
verify(decoded == seeded, "Full scenario round-trips through the persisted snapshot format")
let reply = DemoCompanionService().respond(to: "Was steht heute an?", context: nil, state: seeded, now: testDate)
verify(reply.text.contains("16:00") && reply.text.contains("Offene Aufgaben: 4"), "Companion reads current-day time and deduplicated live tasks")
var edited = seeded
let therapy = edited.nodes.first { $0.history?.dayID == "P217" && $0.history?.entryNumber == 1 }!
let appointmentIndex = edited.appointments.firstIndex { $0.id == therapy.appointmentID }!
edited.appointments[appointmentIndex].date = testDate.addingTimeInterval(2*86_400)
let nodeIndex = edited.nodes.firstIndex { $0.id == therapy.id }!
edited.nodes[nodeIndex].date = edited.appointments[appointmentIndex].date
verify(edited.pathDays.first { $0.id == "day-2026-11-05" }?.entries.count == 2 && edited.pathDays.first { $0.id == "day-2026-11-07" }?.entries.count == 1, "Editing a date regroups the actual appointment without duplicating records")
verify(testCalendar.dateComponents([.year], from: seeded.lifeScenario!.birthDate, to: seeded.lifeScenario!.snapshot).year == 33, "Birth date and snapshot describe the supplied 33-year-old person")
let episodes = Set(seeded.nodes.flatMap { $0.history?.episodeIDs ?? [] }.filter { $0.hasPrefix("atemwege-") })
verify(episodes.count == 51 && seeded.pathDays.filter { $0.title == "Grippe" }.count == 2, "51 scenario episodes, with only the two explicitly named influenza days")
var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState(nodes: [PathNode(kind: .task, title: "Bestehender Eintrag")]))) as! [String: Any]
old.removeValue(forKey: "lifeScenario"); old.removeValue(forKey: "lifeDrafts")
let oldData = try JSONSerialization.data(withJSONObject: old)
let restoredOld = try JSONDecoder().decode(AppState.self, from: oldData)
verify(restoredOld.lifeScenario == nil && restoredOld.nodes[0].title == "Bestehender Eintrag", "Existing snapshots decode without replacing their stored records")
let draftResponse = DemoCompanionService().respond(to: "Hilf mir mit der Kostenerstattung", context: nil, state: seeded, now: testDate)
var hasDraftAction = false
if case .draft = draftResponse.action { hasDraftAction = true }
verify(hasDraftAction, "Current reimbursement wording opens a reviewable draft, never submission")
let invitation = PathCompanionPrompt.make(state: seeded, now: testDate)
verify(invitation.contextID == therapy.id && invitation.text.contains("16:00"), "Path bubble selects today's stored appointment and its exact context")
verify(seeded == decoded, "Building a bubble leaves all stored facts unchanged")
var quiet = AppState(fixtureTimeZoneIdentifier: "Europe/Vienna")
quiet.focusContextID = therapy.id
verify(PathCompanionPrompt.make(state: quiet, now: testDate).contextID == nil, "Quiet check-in never inherits a stale item context")
let horizon = testCalendar.date(byAdding: .day, value: 30, to: testDate)!
var upcoming = AppointmentRecord(title: "Lokaler Termin", date: horizon, status: .confirmed)
let upcomingNode = PathNode(kind: .appointment, title: upcoming.title, appointmentID: upcoming.id, date: testDate.addingTimeInterval(-86_400))
quiet.nodes = [upcomingNode]; quiet.appointments = [upcoming]
verify(PathCompanionPrompt.make(state: quiet, now: testDate).contextID == upcomingNode.id, "30-calendar-day boundary is included using the appointment date, not a stale node date")
quiet.appointments[0].date = horizon.addingTimeInterval(1)
verify(PathCompanionPrompt.make(state: quiet, now: testDate).contextID == nil, "Appointments beyond 30 days fall back to a simple check-in")
quiet.appointments[0].date = testDate.addingTimeInterval(3600)
var excluded = true
for status in [AppointmentStatus.cancelled, .requestDraft] {
    quiet.appointments[0].status = status
    excluded = excluded && PathCompanionPrompt.make(state: quiet, now: testDate).contextID == nil
}
quiet.appointments[0].status = .confirmed
for attendance in [Attendance.attended, .notAttended] {
    quiet.appointments[0].attendance = attendance
    excluded = excluded && PathCompanionPrompt.make(state: quiet, now: testDate).contextID == nil
}
quiet.appointments[0].attendance = .unrecorded
quiet.appointments[0].date = testDate.addingTimeInterval(-1)
verify(excluded, "Cancelled, draft and already answered appointments are skipped")
let unanswered = quiet
let pastPrompt = PathCompanionPrompt.make(state: quiet, now: testDate)
let pastResponse = DemoCompanionService.entryResponse(for: upcomingNode, state: quiet, now: testDate)
verify(pastPrompt.contextID == upcomingNode.id && pastResponse.attendanceQuestionID == upcomingNode.id && quiet == unanswered,
       "A recent confirmed visit opens a question for that visit without recording attendance")
var datedTask = PathNode(kind: .task, title: "Unterlagen vorbereiten", date: today.date)
quiet.nodes = [datedTask]; quiet.appointments = []
verify(PathCompanionPrompt.make(state: quiet, now: testDate).contextID == datedTask.id, "An open date-only task remains eligible throughout its calendar day")
var excludedTasks = true
for status in [TaskStatus.completed, .cancelled] {
    quiet.nodes[0].taskStatus = status
    excludedTasks = excludedTasks && PathCompanionPrompt.make(state: quiet, now: testDate).contextID == nil
}
quiet.nodes[0].taskStatus = .open
for date in [Optional<Date>.none, testDate.addingTimeInterval(-86_400), testCalendar.date(byAdding: .day, value: 31, to: testDate)] {
    quiet.nodes[0].date = date
    excludedTasks = excludedTasks && PathCompanionPrompt.make(state: quiet, now: testDate).contextID == nil
}
quiet.nodes = [reminder]
verify(excludedTasks && PathCompanionPrompt.make(state: quiet, now: testDate).contextID == nil, "Done, cancelled, overdue, undated, distant and duplicate task references do not produce upcoming prompts")
let vaccinations = seeded.nodes.filter { $0.vaccination != nil }
verify(vaccinations.count == 9 && Set(vaccinations.compactMap { $0.date.map(testCalendar.startOfDay(for:)) }).count == 8 && vaccinations.filter { $0.vaccination?.disease == "COVID-19" }.count == 5 && vaccinations.filter { $0.vaccination?.disease == "Influenza" }.count == 4, "Nine verified vaccination records, eight dates, five COVID-19 and four influenza")
let combinedVaccinations = seeded.pathDays.first { $0.id == "day-2025-11-03" }!
verify(combinedVaccinations.title == "Impfungen" && combinedVaccinations.entryCount == 2 && combinedVaccinations.haloSegmentCount == 2, "Two vaccinations on 3 November share one exact two-entry day")
let covid2025 = vaccinations.first { $0.vaccination?.batch == "MT0705" }!
let pageTwo = vaccinations.first { $0.vaccination?.batch == "V3H731V" }!
verify(covid2025.vaccination?.product == "COMIRNATY LP.8.1 INJ30 10x6" && covid2025.vaccination?.productNumber == "6062367" && pageTwo.vaccination?.product == "VAXIGRIP TETRA FSPR 0,5ML" && pageTwo.vaccination?.doseLabel == "Dosis 1" && pageTwo.evidence.first?.pageNumber == 2, "Products, batch/PZN, source dose labels and the second PDF page remain distinct")
verify(vaccinations.filter { $0.vaccination?.hasDocumentedTime == false }.count == 2 && covid2025.vaccination?.recordedAtText.contains("14:02") == true && testCalendar.component(.hour, from: covid2025.date!) == 0, "Two date-only vaccinations do not inherit the later record-entry time")
let july = vaccinations.first { $0.vaccination?.batch == "FD6840" }!
verify(july.date == ISO8601DateFormatter().date(from: "2021-07-08T13:33:00Z") && july.vaccination?.recordedAtText.contains("16:37") == true, "Documented summer offset and administration/registration times stay separate")
let pdfSource = seeded.documents.first { $0.bundledPDFName == VaccinationPassSeed.resourceName }!
verify(pdfSource.text.contains("Seite 2") && vaccinations.allSatisfy { $0.evidence.first?.documentID == pdfSource.id } && VaccinationPassSeed.resourceURL(extension: "pdf", bundle: fixtures) != nil, "Every vaccination links its exact native text and original bundled PDF")
let originalScenario = try LifePathSeed.state(now: testDate, calendar: testCalendar, bundle: fixtures, includingVaccinationPass: false)
let unaffected = originalScenario.nodes.filter { $0.history?.category != .vaccination }
verify(originalScenario.nodes.count == 328 && originalScenario.nodes.filter { $0.history?.category == .vaccination }.count == 32 && unaffected.allSatisfy { original in seeded.nodes.first(where: { $0.id == original.id }) == original } && seeded.nodes.allSatisfy { $0.history?.category != .vaccination }, "Only the 32 original placeholders are replaced; all other 296 records are preserved")
var progressing = originalScenario
let manual = PathNode(kind: .task, title: "Mein eigener Schritt")
progressing.nodes.append(manual)
let preservedTask = progressing.nodes.firstIndex { $0.id == LifePathSeed.stableID("P217-2") }!
progressing.nodes[preservedTask].taskStatus = .completed
progressing.lifeDrafts = ["questionnaire": "Meine bestehenden Notizen"]
progressing.composerDraft = "Nicht fertig geschrieben"
progressing.focusContextID = originalScenario.nodes.first { $0.history?.category == .vaccination }!.id
let migrated = try VaccinationPassSeed.updatingDemo(progressing, now: testDate, bundle: fixtures)
let migratedAgain = try VaccinationPassSeed.updatingDemo(migrated, now: testDate.addingTimeInterval(300), bundle: fixtures)
verify(migrated == migratedAgain && migrated.nodes.contains(manual) && migrated.nodes.first(where: { $0.id == LifePathSeed.stableID("P217-2") })?.taskStatus == .completed && migrated.lifeDrafts == progressing.lifeDrafts && migrated.composerDraft == progressing.composerDraft && migrated.lifeScenario == progressing.lifeScenario && migrated.fixtureEpoch == progressing.fixtureEpoch && migrated.focusContextID == nil, "One-time demo migration preserves progress, custom entries, profile, drafts and epoch without duplicates")
let emptyAfterUpdate = try VaccinationPassSeed.updatingDemo(AppState(), now: testDate, bundle: fixtures)
let customAfterUpdate = try VaccinationPassSeed.updatingDemo(restoredOld, now: testDate, bundle: fixtures)
verify(emptyAfterUpdate.nodes.isEmpty && emptyAfterUpdate.documents.isEmpty && customAfterUpdate == restoredOld, "Deleted stores and unrelated existing profiles are never seeded by the vaccination update")
let vaccinationReply = DemoCompanionService().respond(to: "Welche Impfungen gibt es?", context: nil, state: seeded, now: testDate)
verify(vaccinationReply.text.contains("9 Impfungen") && vaccinationReply.text.contains("5 COVID-19") && vaccinationReply.text.contains("4 Influenza") && vaccinationReply.evidence.first?.documentID == pdfSource.id && seeded.schedules.isEmpty && seeded.appointments.count == originalScenario.appointments.count && seeded.uniqueOpenTasks.count == originalScenario.uniqueOpenTasks.count, "Companion reads documented vaccinations without creating boosters, appointments, tasks or medication schedules")
print("38 scenario checks passed; no simulator used.")
