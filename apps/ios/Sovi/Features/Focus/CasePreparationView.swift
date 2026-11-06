import SwiftUI

struct CasePreparationView: View {
    let progress: DemoScenarioProgress
    let openForms: () -> Void
    let openDocuments: () -> Void
    @Environment(SoviStore.self) private var store
    @State private var editingPerson: FormPerson?
    @State private var source: SourceDocument?
    @State private var sourcePage = 1
    @State private var error: String?
    @State private var editedPersonID: UUID?
    private var prep: CasePreparation { progress.preparation ?? CasePreparation() }
    private var person: FormPerson? { store.state.formPeople?.first { $0.id == prep.applicantID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if progress.scenario == .hospital { recommendations }
            if let question = prep.nextQuestion(for: progress) {
                ForEach(question.choices, id: \.0) { choice in
                    Button(choice.1) { perform(.answerCaseQuestion(question.key, choice.0)) }
                        .buttonStyle(SheetPrimaryButtonStyle(tone: .blue)).accessibilityIdentifier("case.answer.\(question.key).\(choice.0)")
                        .id("case.answer.\(question.key).\(choice.0)")
                        .firstChatChoice(choice.0 == question.choices.first?.0)
                }
            } else if progress.finished {
                authority
                if progress.scenario == .care { Button("Angaben zum Antrag ändern") { perform(.restartCaseQuestions) }.frame(minHeight: 44) }
                applicant
                VStack(alignment: .leading, spacing: 12) {
                    Text("Unterlagen und Prüfung").font(.headline)
                    ForEach(prep.documentItems(for: progress)) { item in
                        Toggle(isOn: Binding(get: { prep.checkedDocuments.contains(item.id) }, set: { perform(.setCaseDocument(progress.scenario, item.id, $0)) })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                Text(item.detail).font(.caption).foregroundStyle(SoviTheme.secondary)
                            }
                        }.accessibilityIdentifier("case.document.\(item.id)")
                    }
                }
                if !prep.formIDs(for: progress).isEmpty {
                    Button("Fallbezogenen Formularentwurf öffnen", action: openForms).buttonStyle(SheetPrimaryButtonStyle(tone: .purple)).accessibilityIdentifier("case.forms")
                }
                let missing = store.state.missingCaseItems(progress.scenario)
                if missing.isEmpty {
                    Text("Unterlagen vorbereitet").accessibilityIdentifier("case.missing")
                } else {
                    DisclosureGroup(progress.replyLanguage.localized("Noch offen: \(missing.count) Punkte")) {
                        ForEach(Array(missing.enumerated()), id: \.offset) { _, item in Text(item).font(.subheadline).padding(.vertical, 3) }
                    }.accessibilityIdentifier("case.missing")
                }
            }
        }.sheet(item: $editingPerson, onDismiss: {
            if let id = editedPersonID, store.state.formPeople?.contains(where: { $0.id == id }) == true { perform(.setCaseApplicant(progress.scenario, id)) }
            editedPersonID = nil
        }) { FormPersonEditor(person: $0) }
            .sheet(item: $source) { CaseSourcePDFSheet(document: $0, pageNumber: sourcePage) }
            .sheetError($error)
    }
    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 12) {
            if prep.sourceDocumentID == nil {
                Button("Brief auswählen oder importieren", action: openDocuments).frame(minHeight: 44)
            }
            ForEach(prep.recommendations) { recommendation in
                VStack(alignment: .leading, spacing: 8) {
                    Text(recommendation.evidence.documentTitle).font(.caption.weight(.semibold))
                    Text(recommendation.evidence.locator).font(.caption)
                    Text(recommendation.evidence.quote).textSelection(.enabled)
                    Button("Im Original ansehen") {
                        sourcePage = recommendation.evidence.pageNumber ?? 1
                        source = store.document(id: recommendation.evidence.documentID)
                    }.frame(minHeight: 44).accessibilityIdentifier("case.source.\(recommendation.kind.rawValue)")
                    Button { perform(.reviewCaseRecommendation(recommendation.id, !recommendation.reviewed)) } label: {
                        Label("Quelle geprüft · diesen Schritt vorbereiten", systemImage: recommendation.reviewed ? "checkmark.square.fill" : "square")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.accessibilityValue(recommendation.reviewed ? progress.replyLanguage.localized("Geprüft") : progress.replyLanguage.localized("Noch nicht geprüft"))
                        .disabled(progress.saved).accessibilityIdentifier("case.review.\(recommendation.kind.rawValue)")
                }.padding(16).background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
    @ViewBuilder private var authority: some View {
        if progress.scenario == .care {
            if progress.answers.first != "home" {
                Text(prep.careAuthority.map { progress.replyLanguage.localized("Pflegegeld: \($0)") } ?? progress.replyLanguage.localized("Pflegegeld: zuständige Stelle noch offen")).font(.headline)
                if ["svs", "bvaeb"].contains(prep.answers["payer"] ?? "") {
                    Link("Offizielle Pflegegeldformulare", destination: URL(string: "https://www.oesterreich.gv.at/de/formsearch/form/265")!).frame(minHeight: 44)
                }
                Link("Quelle zur Zuständigkeit", destination: URL(string: CasePreparation.authoritySource)!).frame(minHeight: 44)
            }
            if progress.answers.first != "money" {
                Text(progress.careInVienna ? progress.replyLanguage.localized("Pflege und Betreuung: Fonds Soziales Wien") : progress.replyLanguage.localized("Pflege und Betreuung: regionale Pflegeberatung")).font(.subheadline)
            }
            Link("Informationen zum Antrag", destination: URL(string: CasePreparation.applicationSource)!).frame(minHeight: 44)
        }
    }
    private var applicant: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Person im Antrag", selection: Binding(get: { prep.applicantID }, set: { if let id = $0 { perform(.setCaseApplicant(progress.scenario, id)) } })) {
                Text("Person auswählen").tag(nil as UUID?)
                ForEach(store.state.formPeople ?? []) { p in Text(p.displayName).tag(Optional(p.id)) }
            }.accessibilityIdentifier("case.applicant")
            Button(person == nil ? "Person hinzufügen" : "Angaben bearbeiten") {
                let value = person ?? FormPerson(label: progress.scenario == .care ? progress.replyLanguage.localized("Mutter") : "")
                editedPersonID = value.id; editingPerson = value
            }.frame(minHeight: 44)
            if let person {
                let missing = CasePreparation.missingProfileFields(person, language: progress.replyLanguage)
                if !missing.isEmpty { Text(progress.replyLanguage.localized("Noch ergänzen: \(missing.joined(separator: ", "))")).font(.caption) }
            }
        }
    }
    private func perform(_ command: AppCommand) {
        do { try store.perform(command) } catch { self.error = error.localizedDescription }
    }
}
