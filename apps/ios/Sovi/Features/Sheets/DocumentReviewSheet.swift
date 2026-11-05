import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentReviewSheet: View {
    var onChooseForCase: ((UUID) -> Void)?
    @Environment(SoviStore.self) private var store
    @State private var selectedID: UUID?
    @State private var showsImporter = false
    @State private var showsManualEntry = false
    @State private var showsPDF = false
    @State private var error: String?
    @State private var showsCase = false

    private var selectedDocument: SourceDocument? {
        selectedID.flatMap { store.document(id: $0) }
    }

    var body: some View {
        SheetPage(title: "Dokumente") {
            if let document = selectedDocument {
                documentContent(document)
            } else {
                chooser
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.plainText, .pdf],
                      allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                try importFile(url)
            } catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: $showsManualEntry) { NodeEditorSheet(kind: .task) }
        .sheet(isPresented: $showsPDF) {
            if let document = selectedDocument { CaseSourcePDFSheet(document: document) }
        }
        .sheet(isPresented: $showsCase) { DemoScenarioChat(scenario: .hospital) }
        .sheetError($error)
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button { showsImporter = true } label: {
                Label("Dokument importieren", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SheetPrimaryButtonStyle())

            if !store.state.documents.isEmpty {
                ForEach(store.state.documents) { document in
                    Button { selectedID = document.id } label: {
                        Label(document.displayTitle, systemImage: "doc.text")
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }

            DisclosureGroup("Weitere Dokumente") {
                ForEach(["A", "B", "C"], id: \.self) { identifier in
                    Button {
                        do { selectedID = try store.fixture(identifier).id }
                        catch { self.error = error.localizedDescription }
                    } label: {
                        Label(LocalizedStringKey(fixtureTitle(identifier)), systemImage: "doc.text")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("documents.fixture.\(identifier)")
                }
            }
        }
    }

    private func documentContent(_ document: SourceDocument) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Button { selectedID = nil } label: {
                Label("Zurück", systemImage: "arrow.left")
                    .frame(minHeight: 44)
            }
            Text(document.displayTitle).font(.title2.bold())
            if document.bundledPDFName != nil || document.importedPDFData != nil {
                Button("PDF öffnen") { showsPDF = true }.frame(minHeight: 44)
            }

            if !DischargeNavigationExtractor.recommendations(in: document).isEmpty {
                Button("Empfehlungen für meine Nachsorge prüfen") {
                    if let onChooseForCase { onChooseForCase(document.id) }
                    else {
                        do { try store.perform(.useCaseDocument(document.id)); showsCase = true }
                        catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("documents.case")
            }

            DisclosureGroup("Originaltext") {
                Text(document.text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding(.top, 14)
            }

            if document.proposals.isEmpty && document.bundledPDFName == nil {
                SheetSection(title: "Keine Vorschläge") {
                    Button("Schritt hinzufügen") { showsManualEntry = true }
                        .frame(minHeight: 44)
                }
            } else if !document.proposals.isEmpty {
                Text("Vorschläge").font(.headline)
                ForEach(document.proposals) { proposal in
                    ProposalReviewCard(documentID: document.id, proposalID: proposal.id)
                }
            }
        }
    }

    private func fixtureTitle(_ id: String) -> String {
        switch id {
        case "A": "Entlassungsbrief A"
        case "B": "Entlassungsbrief B"
        default: "Dokument C"
        }
    }

    private func importFile(_ url: URL) throws {
        let input = try CaseDocumentImport.read(url)
        selectedID = try store.importText(input.text, title: url.lastPathComponent, pdfData: input.pdf, pageSpans: input.pageSpans).id
    }

    private func importError(_ message: String) -> NSError {
        NSError(domain: "Sovi.DocumentImport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private struct ProposalReviewCard: View {
    @Environment(SoviStore.self) private var store
    let documentID: UUID
    let proposalID: UUID
    @State private var editedTitle = ""
    @State private var sourceReviewed = false
    @State private var error: String?

    private var proposal: PlanProposal? {
        store.document(id: documentID)?.proposals.first { $0.id == proposalID }
    }

    var body: some View {
        if let proposal {
            SheetSection(title: proposal.kind.displayTitle) {
                if proposal.status == .pending {
                    TextField("Titel", text: $editedTitle, axis: .vertical)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(proposal.displayTitle).font(.headline)
                }
                if !proposal.displayDetail.isEmpty { Text(proposal.displayDetail).font(.subheadline) }
                DisclosureGroup("Quelle") {
                    ForEach(proposal.evidence) { evidence in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(evidence.displayDocumentTitle) · \(evidence.locator)")
                                .font(.caption.weight(.semibold))
                            Text(evidence.quote).textSelection(.enabled)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SoviTheme.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                if proposal.kind == .medication {
                    if proposal.status == .pending {
                        Toggle("Dosierung, Zeiten und Dauer geprüft", isOn: $sourceReviewed)
                    }
                }
                if proposal.status == .pending {
                    Button {
                        do {
                            try store.perform(.approveProposal(documentID: documentID, proposalID: proposalID,
                                                                revision: proposal.revision, editedTitle: editedTitle))
                        } catch { self.error = error.localizedDescription }
                    } label: {
                        Label("Übernehmen", systemImage: "checkmark")
                    }
                    .buttonStyle(SheetPrimaryButtonStyle())
                    .disabled((proposal.kind == .medication && !sourceReviewed) || editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("proposals.approve.\(proposalID.uuidString)")

                    Button("Ablehnen", role: .destructive) {
                        do {
                            try store.perform(.rejectProposal(documentID: documentID, proposalID: proposalID,
                                                               revision: proposal.revision))
                        } catch { self.error = error.localizedDescription }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("proposals.reject.\(proposalID.uuidString)")
                } else {
                    Label(proposal.status.displayTitle, systemImage: proposal.status == .approved ? "checkmark.circle" : "xmark.circle")
                        .font(.headline)
                }
            }
            .onAppear { if editedTitle.isEmpty { editedTitle = proposal.displayTitle } }
            .sheetError($error)
        }
    }
}
