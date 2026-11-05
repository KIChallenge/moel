import SwiftUI
import PDFKit

struct FormLibrarySheet: View {
    @Environment(SoviStore.self) private var store
    @State private var forms: [PrototypeForm] = []
    @State private var selectedPersonID: UUID?
    @State private var editingPerson: FormPerson?
    @State private var showsWelcome = false
    @State private var error: String?
    var suggestedFormID: String?
    var requiresPersonSelection = false
    var caseScenario: DemoScenario?

    var body: some View {
        SheetPage(title: "Profile und Formulare") {
            Text("Gespeicherte Angaben werden nur auf diesem Gerät für Entwürfe verwendet. Wähle zuerst die Person, für die das Formular bestimmt ist.").font(.subheadline)
            Picker("Person im Antrag", selection: $selectedPersonID) {
                Text("Person auswählen").tag(nil as UUID?)
                ForEach(store.state.formPeople ?? []) { person in Text(person.displayName).tag(Optional(person.id)) }
            }.accessibilityIdentifier("forms.person")
            HStack {
                if let person = selectedPerson { Button("Angaben bearbeiten") { editingPerson = person }.frame(minHeight: 44) }
                Button("Person hinzufügen") { editingPerson = FormPerson(label: String(localized: "Angehörige Person")) }.frame(minHeight: 44)
            }
            if store.state.welcome != nil {
                Button("Willkommensgespräch ansehen") { showsWelcome = true }.frame(minHeight: 44)
            }
            ForEach(orderedForms) { form in
                if let person = selectedPerson {
                    NavigationLink {
                        PrototypeFormEditor(form: form, person: person, caseScenario: caseScenario)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(form.displayTitle, systemImage: "doc.text")
                            Text("Entwurf vorbereiten · \(form.pages) Seiten").font(.caption)
                        }.frame(minHeight: 56)
                    }.accessibilityIdentifier("forms.open.\(form.id)")
                }
            }
            if selectedPerson == nil { Text("Lege ein Profil an oder wähle eine Person. Unbekannte Angaben dürfen leer bleiben.") }
        }.task {
            do {
                forms = try PrototypeForm.load()
                if let caseScenario { selectedPersonID = store.state.demoScenarios?[caseScenario.rawValue]?.preparation?.applicantID }
                else if !requiresPersonSelection { selectedPersonID = store.state.formPeople?.first?.id }
            }
            catch { self.error = error.localizedDescription }
        }
        .sheet(item: $editingPerson, onDismiss: { if selectedPersonID == nil { selectedPersonID = store.state.formPeople?.last?.id } }) { FormPersonEditor(person: $0) }
        .sheet(isPresented: $showsWelcome) { WelcomeChatView() }
        .onChange(of: selectedPersonID) { _, id in
            if let id, let caseScenario {
                do { try store.perform(.setCaseApplicant(caseScenario, id)) } catch { self.error = error.localizedDescription }
            }
        }
        .sheetError($error)
    }
    private var selectedPerson: FormPerson? { store.state.formPeople?.first { $0.id == selectedPersonID } }
    private var orderedForms: [PrototypeForm] {
        let filtered: [PrototypeForm]
        if let caseScenario, let progress = store.state.demoScenarios?[caseScenario.rawValue] {
            filtered = forms.filter { progress.preparation?.formIDs(for: progress).contains($0.id) == true }
        } else { filtered = forms }
        return filtered.sorted { ($0.id == suggestedFormID ? 0 : 1) < ($1.id == suggestedFormID ? 0 : 1) }
    }
}

struct FormPersonEditor: View {
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var person: FormPerson
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Nur auf diesem Gerät. Dieses Profil wird nicht mit der fiktiven Lebensgeschichte oder dem Online-Chat zusammengeführt.").font(.caption)
                    TextField("Profilbezeichnung (z. B. Mutter)", text: $person.label)
                }
                Section("Häufige Angaben") { ForEach(Array(PersonField.allCases.prefix(11))) { field in personInput(field) } }
                Section("Weitere Angaben · freiwillig") { ForEach(Array(PersonField.allCases.dropFirst(11))) { field in personInput(field) } }
            }.navigationTitle("Angaben prüfen")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                        do { try store.perform(.savePerson(person)); dismiss() } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("profile.save") }
                }.sheetError($error)
        }
    }
    private func personInput(_ field: PersonField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.title).font(.caption).foregroundStyle(SoviTheme.secondary)
            TextField(field.title, text: Binding(get: { person.values[field.rawValue] ?? "" }, set: { person.values[field.rawValue] = $0 }))
                .autocorrectionDisabled().textInputAutocapitalization(field == .email ? .never : .sentences)
                .accessibilityIdentifier("profile.\(field.rawValue)")
        }
    }
}

struct PrototypeFormEditor: View {
    let form: PrototypeForm
    let person: FormPerson
    var caseScenario: DemoScenario?
    @Environment(SoviStore.self) private var store
    @State private var values: [String: String] = [:]
    @State private var loaded = false
    @State private var openedEpoch: Date?
    @State private var preview: PDFDocument?
    @State private var showsPreview = false
    @State private var shared: SharedFile?
    @State private var error: String?
    @State private var saved = false
    @State private var purpose = ""
    private var selections: [String: String] { purpose.isEmpty ? [:] : ["Antrag Pflg": purpose] }
    private var key: String { form.id + ":" + person.id.uuidString }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Entwurf · nicht eingereicht", systemImage: "pencil.and.outline").font(.headline)
                Text(person.displayName).font(.title2.bold())
                if let caseScenario {
                    Text(caseScenario.title).font(.subheadline)
                    Text("Dieser Entwurf wird mit deinem Vorgang verbunden. Gespeichert heißt noch nicht unterschrieben oder eingereicht.").font(.caption)
                }
                Text(form.displayNote).font(.subheadline)
                if form.id == "pflegegeld" {
                    Picker("Antragsart prüfen", selection: $purpose) {
                        Text("Noch offen").tag("")
                        Text("Erster Antrag").tag("01")
                        Text("Erhöhung").tag("02")
                        Text("Weitergewährung nach Befristung").tag("03")
                    }.accessibilityIdentifier("form.purpose")
                }
                Text("Die Antragsart bleibt hier zur Prüfung gespeichert. Bitte das passende Kästchen im PDF selbst ankreuzen. Auswahlfelder, Erklärungen und Unterschriften bleiben im Export offen.").font(.caption)
                ForEach(0..<form.pages, id: \.self) { page in
                    let fields = form.fields.filter { $0.page == page }
                    if !fields.isEmpty {
                        DisclosureGroup("Seite \(page + 1) · \(fields.count) Textfelder", isExpanded: Binding(get: { page == 0 || expandedPages.contains(page) }, set: { if $0 { expandedPages.insert(page) } else { expandedPages.remove(page) } })) {
                            ForEach(fields) { field in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(field.label).font(.caption).foregroundStyle(SoviTheme.secondary)
                                    TextField(field.label, text: Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0; saved = false }), axis: .vertical)
                                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("form.field.\(field.id)")
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
                Button("PDF prüfen") { do { preview = try form.document(values: values); showsPreview = true } catch { self.error = error.localizedDescription } }
                    .buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("form.preview")
                Button("Entwurf speichern") { save() }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("form.save")
                Button("PDF-Entwurf teilen") {
                    guard save() else { return }
                    do { shared = SharedFile(url: try form.export(values: values)) } catch { self.error = error.localizedDescription }
                }.frame(minHeight: 44).accessibilityIdentifier("form.export")
                if saved { Label("Gespeichert", systemImage: "checkmark.circle") }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(SoviTheme.background).foregroundStyle(SoviTheme.ink).navigationTitle(form.displayTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Speichern") { save() }.accessibilityIdentifier("form.save.top")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("PDF prüfen") { do { preview = try form.document(values: values); showsPreview = true } catch { self.error = error.localizedDescription } }
                        .accessibilityIdentifier("form.preview.top")
                }
            }
            .onAppear {
                if !loaded {
                    openedEpoch = store.state.fixtureEpoch
                    values = store.state.formDrafts?[key]?.values ?? form.prefill(person)
                    if let existing = store.state.formDrafts?[key] { purpose = existing.selections?["Antrag Pflg"] ?? "" }
                    else if let caseScenario, form.id == "pflegegeld" {
                        let answer = store.state.demoScenarios?[caseScenario.rawValue]?.preparation?.answers["purpose"]
                        purpose = answer == "first" ? "01" : answer == "increase" ? "02" : ""
                    }
                    loaded = true
                }
            }
            .sheet(isPresented: $showsPreview) {
                NavigationStack {
                    if let preview { FormPDFPreview(document: preview).navigationTitle("Entwurf prüfen").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showsPreview = false } } } }
                }
            }
            .sheet(item: $shared) { ActivityShareSheet(file: $0.url) }.sheetError($error)
            .onChange(of: purpose) { _, _ in saved = false }
    }
    @State private var expandedPages: Set<Int> = []
    @discardableResult private func save() -> Bool {
        do {
            guard openedEpoch == store.state.fixtureEpoch else { throw SoviError.staleProposal }
            if let caseScenario { try store.perform(.setCaseApplicant(caseScenario, person.id)) }
            try store.perform(.saveFormDraft(key, SavedFormDraft(formID: form.id, personID: person.id, values: values, caseScenario: caseScenario?.rawValue, selections: selections)))
            saved = true; return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

private struct FormPDFPreview: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        // Editing happens in the labeled text inputs; the preview is a review surface.
        for i in 0..<document.pageCount { document.page(at: i)?.annotations.forEach { if $0.type == "Widget" { $0.isReadOnly = true } } }
        view.document = document; return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

extension PrototypeForm {
    var displayTitle: String { NSLocalizedString(title, comment: "Bundled form title") }
    var displayNote: String { NSLocalizedString(note, comment: "Bundled form scope") }
}
