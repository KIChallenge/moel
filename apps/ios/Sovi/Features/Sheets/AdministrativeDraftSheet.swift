import SwiftUI

struct AdministrativeDraftSheet: View {
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var initialText = ""
    @State private var loaded = false
    @State private var openedEpoch: Date?
    @State private var sharedFile: SharedFile?
    @State private var error: String?
    @State private var showsSaved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Entwurf · nicht eingereicht", systemImage: "pencil.and.outline")
                        .font(.headline)
                        .accessibilityIdentifier("draft.status")
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 330)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(SoviTheme.softGreen.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityLabel("Entwurf bearbeiten")
                        .accessibilityIdentifier("draft.editor")

                    if text.contains("[") {
                        SheetSection(title: "Offene Angaben") {
                            Text("Bitte markierte Felder ergänzen.")
                        }
                    }

                    Button {
                        do {
                            try validateDraftContext()
                            try store.perform(.saveDraft(text))
                            sharedFile = SharedFile(url: try DraftExportFiles.write(text))
                        } catch { self.error = error.localizedDescription }
                    } label: {
                        Label("Textdatei teilen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SheetPrimaryButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("draft.export")

                    if showsSaved { Label("Gespeichert", systemImage: "checkmark.circle") }
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(SoviTheme.background)
            .foregroundStyle(SoviTheme.ink)
            .navigationTitle("Anfrage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        saveAndClose()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        do {
                            try validateDraftContext()
                            try store.perform(.saveDraft(text))
                            initialText = text
                            showsSaved = true
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        .onAppear {
            if !loaded {
                text = store.state.draft?.text ?? store.applicationDraftTemplate()
                initialText = text
                openedEpoch = store.state.fixtureEpoch
                loaded = true
            }
        }
        .onChange(of: text) { _, _ in showsSaved = false }
        .onDisappear {
            if loaded, openedEpoch == store.state.fixtureEpoch, text != initialText {
                do { try store.perform(.saveDraft(text)) }
                catch { store.errorMessage = error.localizedDescription }
            }
        }
        .sheet(item: $sharedFile) { file in ActivityShareSheet(file: file.url) }
        .sheetError($error)
    }

    private func saveAndClose() {
        do {
            try validateDraftContext()
            if text != initialText { try store.perform(.saveDraft(text)) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func validateDraftContext() throws {
        guard openedEpoch == store.state.fixtureEpoch else {
            throw SoviError.invalidInput("Die Daten wurden geändert. Bitte den Entwurf erneut öffnen.")
        }
    }
}
