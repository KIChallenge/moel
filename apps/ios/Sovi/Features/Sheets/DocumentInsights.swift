import SwiftUI

struct DocumentInsights: View {
    let document: SourceDocument
    let language: ChatLanguage
    @Environment(SoviStore.self) private var store
    @State private var reading: DocumentDiscussion.Reading?
    @State private var selection: Set<UUID> = []
    @State private var error: String?
    @State private var formID: String?
    @State private var showsCare = false
    @State private var inspecting: EvidenceReference?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if document.pageSpans?.contains(where: { $0.usedTextRecognition == true }) == true {
                Text(language.text("Text aus einem Scan. Bitte mit dem Original vergleichen.")).font(.caption)
            }
            switch reading {
            case .report(let report): reportView(report)
            case .vaccinations(let pass): vaccinationView(pass)
            default: EmptyView()
            }
            if saved { Label(language.text("Im Pfad gespeichert"), systemImage: "checkmark").accessibilityIdentifier("documents.saved") }
        }
        .task(id: language.rawValue) {
            reading = DocumentDiscussion.read(document, language: language, calendar: store.state.pathCalendar)
        }
        .sheet(item: $inspecting) { EvidenceSheet(evidence: $0) }
        .sheet(isPresented: Binding(get: { formID != nil }, set: { if !$0 { formID = nil } })) {
            if let formID {
                FormLibrarySheet(suggestedFormID: formID, requiresPersonSelection: true, sourceDocumentID: document.id)
                    .environment(\.locale, Locale(identifier: language.rawValue))
            }
        }
        .sheet(isPresented: $showsCare) { DemoScenarioChat(scenario: .care) }
        .sheetError($error)
    }

    @ViewBuilder private func reportView(_ report: BefundReview) -> some View {
        Text(report.explanation).accessibilityIdentifier("documents.explanation")
        ForEach(report.passages) { passage in
            source(passage)
        }
        if !report.actions.isEmpty {
            Text(language.text("Schritte aus dem Befund")).font(.headline)
            ForEach(report.actions) { item in
                let adopted = BefundReader.isAdopted(item, in: store.state)
                choice(item.id, title: item.title, detail: nil, added: adopted)
                source(item.evidence)
                if let form = item.formID {
                    Button { formID = form } label: { Label(language.text("Passendes Formular"), systemImage: "doc.text") }
                        .frame(minHeight: 44).accessibilityIdentifier("documents.form." + form)
                }
            }
            if report.actions.contains(where: \.isCareRequest) {
                Button(language.text("Pflegeantrag vorbereiten")) {
                    do {
                        try store.perform(.linkCareReport(document.id, language))
                        showsCare = true
                    } catch { self.error = error.localizedDescription }
                }.frame(minHeight: 44)
            }
            saveButton("Ausgewählte Schritte hinzufügen") {
                try store.perform(.adoptBefundActions(documentID: document.id, selectedIDs: selection, language: language.rawValue))
            }
        }
    }

    @ViewBuilder private func vaccinationView(_ pass: VaccinationPassReview) -> some View {
        Text(language.text("Dokumentierte Impfungen") + " (\(pass.entries.count))").font(.headline)
        if let holder = pass.holder { Text(holder).font(.subheadline) }
        Text(language.text("Prüfe Person und Impfdatum, bevor du Einträge zu diesem Pfad hinzufügst.")).font(.subheadline)
        ForEach(pass.entries) { item in
            let adopted = VaccinationImport.isRecorded(item, in: store.state, document: document)
            choice(item.id, title: item.record.disease.isEmpty ? item.record.product : item.record.disease, detail: [item.record.administrationText, item.record.product].joined(separator: " · "), added: adopted)
            source(item.evidence)
        }
        if pass.unreadableRows > 0 { Text(language.text("Bitte unvollständige Zeilen im Original prüfen.")) }
        let remaining = Set(pass.entries.filter { !VaccinationImport.isRecorded($0, in: store.state, document: document) }.map(\.id))
        if !remaining.isEmpty {
            Button(selection == remaining ? language.text("Auswahl aufheben") : language.text("Alle auswählen")) {
                selection = selection == remaining ? [] : remaining
                saved = false
            }.accessibilityIdentifier("documents.selectAllVaccines")
            saveButton("Impfungen zum Pfad hinzufügen") {
                try store.perform(.importVaccinations(documentID: document.id, selectedIDs: selection))
            }
        }
    }

    private func choice(_ id: UUID, title: String, detail: String?, added: Bool) -> some View {
        Toggle(isOn: Binding(get: { added || selection.contains(id) }, set: { selected in
            if selected { selection.insert(id) } else { selection.remove(id) }
            saved = false
        })) {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.subheadline) }
                if added { Text(language.text("Im Pfad gespeichert")).font(.caption) }
            }
        }
        .disabled(added).accessibilityIdentifier("documents.select." + id.uuidString)
    }

    private func source(_ evidence: EvidenceReference) -> some View {
        Button { inspecting = evidence } label: {
            Label(evidence.quote, systemImage: "doc.text.magnifyingglass").font(.subheadline).multilineTextAlignment(.leading)
        }
        .accessibilityHint(Text(language.text("Originaltext öffnen")))
    }

    private func saveButton(_ key: String, action: @escaping () throws -> Void) -> some View {
        Button(language.text(key)) {
            do { try action(); selection = []; saved = true }
            catch { self.error = error.localizedDescription }
        }
        .buttonStyle(SheetPrimaryButtonStyle()).disabled(selection.isEmpty)
        .accessibilityIdentifier("documents.apply")
    }
}
