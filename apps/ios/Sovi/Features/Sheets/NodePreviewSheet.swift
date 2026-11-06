import SwiftUI

struct NodePreviewSheet: View {
    let nodeID: UUID
    let onFocus: (UUID) -> Void
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showsDocuments = false
    @State private var showsEditor = false
    @State private var showsReminderControls = false
    @State private var selectedEvidence: EvidenceReference?
    @State private var appointmentToEdit: AppointmentRecord?
    @State private var occurrenceToEdit: OccurrenceSelection?
    @State private var error: String?
    @State private var scenario: DemoScenario?

    var body: some View {
        SheetPage(title: "Eintrag", startsCompact: true) {
            if let node = store.node(id: nodeID) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(node.vaccination == nil ? node.history.map { NSLocalizedString($0.category.rawValue, comment: "Entry category") } ?? node.kind.displayTitle : String(localized: "Impfung"),
                          systemImage: node.vaccination == nil ? node.kind.symbol : "syringe.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SoviTheme.secondary)
                    Text(node.displayTitle).font(.system(.title, design: .rounded, weight: .bold))
                    if node.vaccination == nil && node.kind != .appointment && !node.displayDetail.isEmpty {
                        Text(node.displayDetail).foregroundStyle(SoviTheme.secondary)
                    }
                    if let date = node.date, node.kind != .appointment, node.vaccination == nil {
                        Text(date, format: .dateTime.day().month(.wide).year())
                            .font(.subheadline)
                    }
                }

                if let vaccination = node.vaccination {
                    VaccinationDetails(record: vaccination)
                } else if node.history != nil {
                    LifeRecordContext(node: node, onFocus: onFocus)
                    switch node.kind {
                    case .task: taskContent(node)
                    case .appointment: appointmentContent(node)
                    case .information: historicalReadContent(node)
                    default: EmptyView()
                    }
                } else {
                    switch node.kind {
                    case .task: taskContent(node)
                    case .information: informationContent(node)
                    case .appointment: appointmentContent(node)
                    case .medication: medicationContent(node)
                    case .event: eventContent(node)
                    }
                }

                if let progress = store.state.demoScenarios?.values.first(where: { progress in
                    progress.saved && progress.steps.indices.contains(where: { progress.taskID($0) == node.id })
                }) {
                    Button("Vorgang öffnen") { scenario = progress.scenario }.frame(minHeight: 44).accessibilityIdentifier("preview.scenario")
                }

                if !store.evidence(for: node).isEmpty {
                    SheetSection(title: "Quelle") {
                        ForEach(store.evidence(for: node)) { evidence in
                            Button { selectedEvidence = evidence } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Label(evidence.displayDocumentTitle, systemImage: "text.quote")
                                        .font(.subheadline.weight(.semibold))
                                    Text(evidence.locator).font(.caption)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("preview.source.\(evidence.id.uuidString)")
                        }
                    }
                }

                Button {
                    dismiss()
                    onFocus(node.id)
                } label: {
                    Label("Sovi fragen", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(SheetPrimaryButtonStyle())
                .accessibilityIdentifier("preview.focus")

            } else {
                ContentUnavailableView("Eintrag nicht gefunden", systemImage: "leaf")
            }
        }
        .sheet(isPresented: $showsDocuments) { DocumentReviewSheet() }
        .sheet(isPresented: $showsEditor) { NodeEditorSheet(kind: .task) }
        .sheet(isPresented: $showsReminderControls) { LocalControlsSheet() }
        .sheet(item: $selectedEvidence) { evidence in EvidenceSheet(evidence: evidence) }
        .sheet(item: $appointmentToEdit) { appointment in AppointmentEditorSheet(appointment: appointment) }
        .sheet(item: $occurrenceToEdit) { selection in
            MedicationLogSheet(scheduleID: selection.scheduleID, occurrenceID: selection.occurrenceID)
        }
        .sheet(item: $scenario) { DemoScenarioChat(scenario: $0) }
        .sheetError($error)
    }

    private func taskContent(_ node: PathNode) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetSection(title: "Status") {
                Label(node.taskStatus.displayTitle, systemImage: node.taskStatus == .completed ? "checkmark.circle" : "circle.dotted")
                    .font(.headline)
                Button(node.taskStatus == .completed ? "Wieder öffnen" : "Erledigen") {
                    perform(.setTask(node.id, node.taskStatus == .completed ? .open : .completed))
                }
                .buttonStyle(SheetPrimaryButtonStyle())
                .accessibilityIdentifier("preview.complete")
                Menu("Status ändern") {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Button(status.displayTitle) { perform(.setTask(node.id, status)) }
                    }
                }
                .frame(minHeight: 44)
            }
            TaskDraftButtons(node: node)
            if node.history == nil && (node.title.localizedCaseInsensitiveContains("Unterlagen") || node.detail.localizedCaseInsensitiveContains("Dokument")) {
                Button { showsDocuments = true } label: {
                    Label("Unterlage prüfen", systemImage: "doc.text.magnifyingglass")
                        .frame(minHeight: 44)
                }
            }
            if node.title.localizedCaseInsensitiveContains("Physio") || node.title.localizedCaseInsensitiveContains("Termin") || node.title.localizedCaseInsensitiveContains("Nachkontrolle") {
                AppointmentCreationButton()
            }
        }
    }

    private func historicalReadContent(_ node: PathNode) -> some View {
        SheetSection(title: "Lesestatus") {
            Button(node.informationRead ? "Lesemarkierung zurücknehmen" : "Als gelesen markieren") {
                perform(.markRead(node.id, !node.informationRead))
            }
            .buttonStyle(SheetPrimaryButtonStyle())
            .accessibilityIdentifier("preview.read")
        }
    }

    private func informationContent(_ node: PathNode) -> some View {
        SheetSection(title: "Lesestatus") {
            Button(node.informationRead ? "Lesemarkierung zurücknehmen" : "Als gelesen markieren") {
                perform(.markRead(node.id, !node.informationRead))
            }
            .buttonStyle(SheetPrimaryButtonStyle())
            .accessibilityIdentifier("preview.read")
        }
    }

    @ViewBuilder
    private func appointmentContent(_ node: PathNode) -> some View {
        if let id = node.appointmentID, let appointment = store.state.appointments.first(where: { $0.id == id }) {
            SheetSection(title: "Termin") {
                Text(appointment.date, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                    .font(.title3.weight(.semibold))
                Label(appointment.displayLocation.isEmpty ? String(localized: "Ort offen") : appointment.displayLocation, systemImage: "mappin.and.ellipse")
                LabeledContent("Status", value: appointment.status.displayTitle)
                LabeledContent("Teilnahme", value: appointment.attendance.displayTitle)
                if !appointment.displayPreparation.isEmpty {
                    DisclosureGroup("Vorbereitung") { Text(appointment.displayPreparation) }
                }
                Button("Termin oder Teilnahme bearbeiten") { appointmentToEdit = appointment }
                    .buttonStyle(SheetPrimaryButtonStyle())
                    .accessibilityIdentifier("preview.appointment.edit")
            }
            reminderControls
        } else {
            AppointmentCreationButton()
        }
    }

    @ViewBuilder
    private func medicationContent(_ node: PathNode) -> some View {
        if let id = node.scheduleID, let schedule = store.state.schedules.first(where: { $0.id == id }) {
            SheetSection(title: "Einnahmeplan") {
                Text(schedule.displayTitle).font(.headline)
                if !schedule.displayInstruction.isEmpty { Text(schedule.displayInstruction).textSelection(.enabled) }
                ForEach(schedule.evidence) { evidence in
                    Button("Anweisung ansehen") { selectedEvidence = evidence }
                        .frame(minHeight: 44)
                }
            }
            Text("Einnahmen").font(.headline)
            ForEach(schedule.occurrences) { occurrence in
                SheetSection(title: occurrence.log.displayTitle) {
                    Text(occurrence.date, format: .dateTime.day().month(.wide).year().hour().minute())
                        .font(.headline)
                    if !occurrence.amount.localizedCaseInsensitiveContains("demo") { Text(occurrence.amount) }
                    Button(occurrence.log == .unrecorded ? "Erfassen" : "Bearbeiten") {
                        occurrenceToEdit = OccurrenceSelection(scheduleID: schedule.id, occurrenceID: occurrence.id)
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("medication.occurrence.\(occurrence.id.uuidString)")
                }
            }
            reminderControls
        } else {
            Text("Kein Einnahmeplan")
        }
    }

    @ViewBuilder private func eventContent(_ node: PathNode) -> some View {
        if node.chapter == 3 {
            SheetSection(title: "Aktionen") {
                Button { showsDocuments = true } label: {
                    Label("Entlassungsunterlage prüfen", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(SheetPrimaryButtonStyle())
                .accessibilityIdentifier("preview.documents")
                Button("Schritt hinzufügen") { showsEditor = true }
                    .frame(minHeight: 44)
            }
        }
    }

    private var reminderControls: some View {
        SheetSection(title: "Erinnerungen") {
            Text(store.state.notificationsEnabled ? "Erinnerungen aktiv" : "Erinnerungen aus")
                .font(.footnote).foregroundStyle(SoviTheme.secondary)
            Button("Verwalten") { showsReminderControls = true }
                .frame(minHeight: 44)
        }
    }

    private func perform(_ command: AppCommand) {
        do { try store.perform(command) }
        catch { self.error = error.localizedDescription }
    }
}

struct TaskDraftButtons: View {
    let node: PathNode
    @Environment(SoviStore.self) private var store
    @State private var showsPreparation = false
    @State private var showsDraft = false

    private var hasAdministrativeDraft: Bool {
        let titles = ["Kostenerstattung", "Antrag", "Entwurf", "Verwaltung", "Unterlagen"]
        guard titles.contains(where: node.title.localizedCaseInsensitiveContains) else { return false }
        let belongsToScenario = store.state.demoScenarios?.values.contains { progress in
            progress.steps.indices.contains { progress.taskID($0) == node.id }
        }
        return belongsToScenario != true
    }

    var body: some View {
        if let kind = node.history?.draftKind {
            Button { showsPreparation = true } label: {
                Label(kind == .questionnaire ? "Anamnesebogen öffnen" : "Medikamentenliste öffnen", systemImage: "square.and.pencil")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("preview.preparation")
            .sheet(isPresented: $showsPreparation) { LifePreparationSheet(kind: kind).buttonStyle(.automatic) }
        }
        if hasAdministrativeDraft {
            Button { showsDraft = true } label: {
                Label("Entwurf öffnen", systemImage: "square.and.pencil").frame(minHeight: 44)
            }
            .accessibilityIdentifier("preview.draft")
            .sheet(isPresented: $showsDraft) { AdministrativeDraftSheet().buttonStyle(.automatic) }
        }
    }
}

private struct AppointmentCreationButton: View {
    @State private var showsEditor = false
    var body: some View {
        Button { showsEditor = true } label: {
            Label("Termin hinzufügen", systemImage: "calendar.badge.plus")
                .frame(minHeight: 44)
        }
        .sheet(isPresented: $showsEditor) { NodeEditorSheet(kind: .appointment) }
    }
}

private struct OccurrenceSelection: Identifiable {
    var id: UUID { occurrenceID }
    let scheduleID: UUID
    let occurrenceID: UUID
}

private struct MedicationLogSheet: View {
    let scheduleID: UUID
    let occurrenceID: UUID
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pendingLog: MedicationLog?
    @State private var confirmsLog = false
    @State private var error: String?
    @State private var evidence: EvidenceReference?

    private var schedule: MedicationSchedule? { store.state.schedules.first { $0.id == scheduleID } }
    private var occurrence: MedicationOccurrence? { schedule?.occurrences.first { $0.id == occurrenceID } }

    var body: some View {
        SheetPage(title: "Einnahme") {
            if let schedule, let occurrence {
                Text(schedule.displayTitle).font(.title2.bold())
                Text(occurrence.date, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                    .font(.headline)
                if !occurrence.amount.localizedCaseInsensitiveContains("demo") { Text(occurrence.amount).font(.title3) }
                Label(occurrence.log.displayTitle, systemImage: occurrence.log == .unrecorded ? "circle.dotted" : "pencil.circle")

                Button("Eingenommen") { propose(.taken) }
                    .buttonStyle(SheetPrimaryButtonStyle())
                    .accessibilityIdentifier("medication.taken")
                Button("Nicht eingenommen") { propose(.notTaken) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("medication.notTaken")
                if occurrence.log != .unrecorded {
                    Button("Zurücksetzen") { propose(.unrecorded) }
                        .frame(minHeight: 44)
                }
                if let source = schedule.evidence.first {
                    Button("Anweisung ansehen") { evidence = source }
                        .frame(minHeight: 44)
                }

                if !occurrence.corrections.isEmpty {
                    SheetSection(title: "Änderungsverlauf") {
                        ForEach(occurrence.corrections) { correction in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(correction.previous.displayTitle) → \(correction.value.displayTitle)")
                                Text(correction.date, format: .dateTime.day().month().hour().minute())
                                    .font(.caption).foregroundStyle(SoviTheme.secondary)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Eintrag speichern?", isPresented: $confirmsLog, titleVisibility: .visible) {
            if let pendingLog {
                Button(pendingLog.displayTitle) {
                    do {
                        try store.perform(.recordMedication(scheduleID: scheduleID, occurrenceID: occurrenceID, log: pendingLog))
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .accessibilityIdentifier("medication.confirm")
            }
        } message: {
            if let occurrence {
                Text(occurrence.date.formatted(date: .abbreviated, time: .shortened))
                if !occurrence.amount.localizedCaseInsensitiveContains("demo") { Text(occurrence.amount) }
            }
        }
        .sheet(item: $evidence) { source in EvidenceSheet(evidence: source) }
        .sheetError($error)
    }

    private func propose(_ log: MedicationLog) {
        pendingLog = log
        confirmsLog = true
    }
}
