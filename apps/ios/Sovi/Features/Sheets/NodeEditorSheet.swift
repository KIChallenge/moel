import SwiftUI

struct NodeEditorSheet: View {
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: NodeKind
    @State private var title = ""
    @State private var detail = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var location = ""
    @State private var appointmentStatus: AppointmentStatus = .requestDraft
    @State private var operationID = UUID()
    @State private var error: String?

    init(kind: NodeKind = .task) { self.kind = kind }

    private var editorTitle: String {
        switch kind {
        case .appointment: "Termin eintragen"
        case .event: "Ereignis hinzufügen"
        default: "Schritt hinzufügen"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Titel", text: $title)
                        .accessibilityIdentifier("editor.title")
                    TextField("Notiz", text: $detail, axis: .vertical)
                        .lineLimit(3...7)
                }
                Section("Datum") {
                    if kind != .appointment { Toggle("Datum hinzufügen", isOn: $hasDate) }
                    if hasDate || kind == .appointment {
                        DatePicker("Datum und Uhrzeit", selection: $date)
                    }
                }
                if kind == .appointment {
                    Section("Termin") {
                        TextField("Ort oder Kontakt", text: $location)
                        Picker("Status", selection: $appointmentStatus) {
                            Text("Anfrage").tag(AppointmentStatus.requestDraft)
                            Text("Bestätigt").tag(AppointmentStatus.confirmed)
                        }
                        Text("Nur in Sovi gespeichert.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(Text(LocalizedStringKey(editorTitle)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        do {
                            try store.perform(.addNode(kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       detail: detail, date: hasDate || kind == .appointment ? date : nil,
                                                       location: location, appointmentStatus: appointmentStatus,
                                                       operationID: operationID))
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("editor.save")
                }
            }
        }
        .onAppear { date = store.now }
        .sheetError($error)
    }
}

struct AppointmentEditorSheet: View {
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var appointment: AppointmentRecord
    @State private var error: String?
    @State private var location = ""
    @State private var preparation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    TextField("Titel", text: $appointment.title)
                    DatePicker("Datum und Uhrzeit", selection: $appointment.date)
                    TextField("Ort", text: $location)
                    TextField("Vorbereitung", text: $preparation, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Status", selection: $appointment.status) {
                        Text("Anfrage").tag(AppointmentStatus.requestDraft)
                        Text("Bestätigt").tag(AppointmentStatus.confirmed)
                        Text("Abgesagt").tag(AppointmentStatus.cancelled)
                    }
                }
                Section("Teilnahme") {
                    Picker("Teilnahme", selection: $appointment.attendance) {
                        Text("Nicht erfasst").tag(Attendance.unrecorded)
                        Text("Teilgenommen").tag(Attendance.attended)
                        Text("Nicht teilgenommen").tag(Attendance.notAttended)
                    }
                }
                Section {
                    Text("Nur in Sovi gespeichert.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Termin bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        do {
                            if location != appointment.displayLocation { appointment.location = location }
                            if preparation != appointment.displayPreparation { appointment.preparation = preparation }
                            appointment.provenance = "Lokal eingetragen."
                            try store.perform(.editAppointment(appointment))
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(appointment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            location = appointment.displayLocation
            preparation = appointment.displayPreparation
        }
        .sheetError($error)
    }
}
