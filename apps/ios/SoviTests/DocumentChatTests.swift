import XCTest
import UIKit
import PDFKit
@testable import Sovi

@MainActor
final class DocumentChatTests: XCTestCase {
    /// Local audit when the supplied files are present. Document contents are
    /// never copied into source control, sent to a server, or logged.
    private func suppliedExamples(in folder: String) throws -> [URL] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        root.appendPathComponent("_KI Challenge Daten Use Case 1")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("The supplied local example documents are not installed on this machine.")
        }
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let directory = try XCTUnwrap(directories.first {
            $0.lastPathComponent.precomposedStringWithCanonicalMapping == folder
        })
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testSuppliedMedicalPDFExamplesThroughActualChatImporter() throws {
        let files = try suppliedExamples(in: "Befunde")
        XCTAssertEqual(files.count, 5)
        for url in files {
            let input = try CaseDocumentImport.read(url)
            XCTAssertFalse(input.text.isEmpty, url.lastPathComponent)
            let clock = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-06T08:00:00Z"))
            let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true), clock: { clock })
            let before = store.state
            let imported = try store.importChatAttachment(input, title: url.lastPathComponent, language: .de)
            let document = imported.document
            XCTAssertEqual(document.importedPDFData, try Data(contentsOf: url))
            XCTAssertEqual(store.state.discussedDocumentID, document.id)
            XCTAssertEqual(store.state.appointments, before.appointments)
            XCTAssertEqual(store.state.schedules, before.schedules)
            XCTAssertFalse(imported.eventIDs.isEmpty, "No dated events extracted from \(url.lastPathComponent)")
            for id in imported.eventIDs {
                let event = try XCTUnwrap(store.node(id: id))
                XCTAssertNotNil(event.date)
                XCTAssertTrue(event.evidence.contains { $0.documentID == document.id && document.text.contains($0.quote) })
            }
            let followUp = try XCTUnwrap(DocumentDiscussion.reply(to: "Welche Ereignisse hast du gefunden?", state: store.state, language: .de))
            XCTAssertFalse(followUp.response.text.isEmpty)
            XCTAssertEqual(followUp.documentID, document.id)
            let nodeCount = store.state.nodes.count
            let again = try store.importChatAttachment(input, title: url.lastPathComponent, language: .de)
            XCTAssertEqual(again.eventIDs, imported.eventIDs)
            XCTAssertTrue(again.addedEventIDs.isEmpty)
            XCTAssertEqual(store.state.nodes.count, nodeCount)
            let actions = BefundReader.review(document, language: "de")?.actions.count ?? 0
            let ocrPages = input.pageSpans?.filter { $0.usedTextRecognition == true }.count ?? 0
            let pdf = try XCTUnwrap(input.pdf)
            print("Local document check: \(url.lastPathComponent); pages=\(PDFDocument(data: pdf)?.pageCount ?? 0); OCR pages=\(ocrPages); events=\(imported.eventIDs.count); reviewed actions=\(actions)")
        }
    }

    func testSevenSuppliedBlankFormsStayAttachmentsWithoutFalseLifeEvents() throws {
        let files = try suppliedExamples(in: "Anträge und Formulare")
        XCTAssertEqual(files.count, 7)
        for url in files {
            let input = try CaseDocumentImport.read(url)
            let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true))
            let before = store.state
            let imported = try store.importChatAttachment(input, title: url.lastPathComponent, language: .de)
            XCTAssertFalse(imported.document.text.isEmpty)
            XCTAssertEqual(imported.document.importedPDFData, try Data(contentsOf: url))
            XCTAssertTrue(imported.eventIDs.isEmpty, "Blank form created events: \(url.lastPathComponent)")
            XCTAssertEqual(store.state.nodes, before.nodes)
            XCTAssertEqual(store.state.appointments, before.appointments)
            XCTAssertEqual(store.state.schedules, before.schedules)
            print("Local blank-form check: \(url.lastPathComponent); readable=true; events=\(imported.eventIDs.count)")
        }
    }

    func testChatPDFImportCreatesOnlyDocumentedEventAndPreservesItsSourceAfterReload() throws {
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 490, height: 640)).pdfData { renderer in
            let pages = [
                ["US-Befund", "vom 6. August 2023 um 04:46 Uhr | Version: 1"],
                ["Ambulant am 2. August 2023 FZ: 987", "Befund", "Die Untersuchung ist dokumentiert."]
            ]
            for lines in pages {
                renderer.beginPage()
                for (index, line) in lines.enumerated() {
                    (line as NSString).draw(at: CGPoint(x: 30, y: 30 + CGFloat(index * 26)),
                                            withAttributes: [.font: UIFont.systemFont(ofSize: 15)])
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try pdf.write(to: url)
        let input = try CaseDocumentImport.read(url)
        let container = try SoviStore.makeContainer(inMemory: true)
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-05T08:00:00Z"))
        let store = try SoviStore(container: container, clock: { instant })
        try store.perform(.saveComposer("My next question"))
        let before = store.state
        let result = try store.importChatAttachment(input, title: "scan.pdf", language: .en)
        XCTAssertEqual(result.eventIDs.count, 1)
        XCTAssertEqual(result.addedEventIDs, result.eventIDs)
        let id = try XCTUnwrap(result.eventIDs.first)
        let event = try XCTUnwrap(store.node(id: id))
        XCTAssertEqual(event.kind, .event)
        XCTAssertEqual(store.state.nodes.count, before.nodes.count + 1)
        XCTAssertEqual(store.state.appointments, before.appointments)
        XCTAssertEqual(store.state.schedules, before.schedules)
        XCTAssertTrue(store.state.compactPathDays.contains { $0.id == "day-2023-08-02" && $0.entries.contains { $0.id == id } })
        let evidence = try XCTUnwrap(event.evidence.first)
        XCTAssertEqual(evidence.documentID, result.document.id)
        XCTAssertEqual(evidence.pageNumber, 2)
        XCTAssertTrue(evidence.quote.contains("Ambulant am 2. August 2023"))
        XCTAssertTrue(result.document.text.contains(evidence.quote))
        XCTAssertEqual(result.document.importedPDFData, pdf)
        XCTAssertEqual(store.state.conversation.dropLast().last?.attachmentDocumentID, result.document.id)
        XCTAssertEqual(store.state.conversation.last?.attachmentEventIDs, result.eventIDs)
        XCTAssertEqual(store.state.discussedDocumentID, result.document.id)
        XCTAssertEqual(store.state.composerDraft, before.composerDraft)

        let restored = try SoviStore(container: container, clock: { instant })
        XCTAssertEqual(restored.node(id: id), event)
        XCTAssertEqual(restored.document(id: result.document.id)?.importedPDFData, pdf)
        let question = "What date was the examination?"
        let answer = try XCTUnwrap(DocumentDiscussion.reply(to: question, state: restored.state, language: .en))
        XCTAssertEqual(answer.documentID, result.document.id)
        XCTAssertEqual(answer.response.entryIDs, [id])
        XCTAssertTrue(answer.response.text.contains(event.displayTitle))
        XCTAssertTrue(answer.response.text.contains("2023"))
        try restored.perform(.discussDocument(documentID: answer.documentID, question: question, reply: answer.response.text,
                                              eventIDs: answer.response.entryIDs))
        XCTAssertEqual(restored.state.conversation.last?.replyDocumentID, result.document.id)
        XCTAssertEqual(restored.state.conversation.last?.attachmentEventIDs, [id])
        let archive = DocumentDiscussion.attachments(in: restored.state)
        XCTAssertEqual(archive.count, 1, "A question about an attachment should not create another attachment.")
        XCTAssertEqual(archive.first?.reply.attachmentEventIDs, [id])
        let repeated = try restored.importChatAttachment(input, title: "renamed.pdf", language: .de)
        XCTAssertEqual(repeated.document.id, result.document.id)
        XCTAssertEqual(repeated.eventIDs, [id])
        XCTAssertTrue(repeated.addedEventIDs.isEmpty)
        XCTAssertEqual(restored.state.nodes.count, before.nodes.count + 1)
        XCTAssertEqual(restored.node(id: id), event)
    }

    func testChatKeepsAnUnmatchedFormAsAnAttachmentWithoutInventingEvents() throws {
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true))
        let before = store.state
        let text = "Antrag auf Förderung\nGeburtsdatum: 13.02.1960\nGeplante Aufnahme: 01.10.2026\nBitte hier unterschreiben."
        let result = try store.importChatAttachment((text, nil, nil), title: "Formular.txt", language: .en)
        XCTAssertTrue(result.eventIDs.isEmpty)
        XCTAssertEqual(store.document(id: result.document.id)?.text, text)
        XCTAssertEqual(store.state.nodes, before.nodes)
        XCTAssertEqual(store.state.conversation.dropLast().last?.attachmentDocumentID, result.document.id)
        XCTAssertEqual(store.state.conversation.last?.text, result.reply)
        let saved = store.state
        XCTAssertThrowsError(try store.importChatAttachment(("", nil, nil), title: "empty.txt", language: .en))
        XCTAssertEqual(store.state, saved)
    }

    func testChatImpfpassImportUsesAdministrationDatesAndPromotesSeedEventsOnlyOnce() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-05T08:00:00Z"))
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true), clock: { instant })
        let input = try CaseDocumentImport.read(XCTUnwrap(VaccinationPassSeed.resourceURL(extension: "pdf")))
        let baseline = store.state.nodes.count
        let result = try store.importChatAttachment(input, title: "Impfpass.pdf", language: .en)
        XCTAssertEqual(Set(result.eventIDs).count, 9)
        XCTAssertEqual(store.state.nodes.count, baseline)
        XCTAssertTrue(store.state.compactPathDays.contains { $0.id == "day-2022-12-04" })
        let vaccination = try XCTUnwrap(result.eventIDs.compactMap { store.node(id: $0) }.first { $0.vaccination?.batch == "V3H731V" })
        XCTAssertEqual(vaccination.date, ISO8601DateFormatter().date(from: "2021-11-17T13:43:00+01:00"))
        XCTAssertEqual(vaccination.evidence.first?.pageNumber, 2)
        let repeated = try store.importChatAttachment(input, title: "copy.pdf", language: .en)
        XCTAssertEqual(Set(repeated.eventIDs), Set(result.eventIDs))
        XCTAssertTrue(repeated.addedEventIDs.isEmpty)
        XCTAssertEqual(store.state.nodes.count, baseline)
    }

    func testReportQuestionReopensSourceAndReturnsRelevantFormInSelectedLanguage() throws {
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true))
        let input = try CaseDocumentImport.read(CaseDocumentImport.sampleURL())
        let report = try store.importText(input.text, title: "Befund.pdf", pdfData: input.pdf, pageSpans: input.pageSpans)
        let question = "Can you explain my medical report?"
        let reply = try XCTUnwrap(DocumentDiscussion.reply(to: question, state: store.state, language: .en))
        XCTAssertEqual(reply.documentID, report.id)
        XCTAssertTrue(reply.response.text.localizedCaseInsensitiveContains("rehabilitation"))
        try store.perform(.discussDocument(documentID: reply.documentID, question: question, reply: reply.response.text))
        let next = try XCTUnwrap(DocumentDiscussion.reply(to: "Which form do I need?", state: store.state, language: .en))
        XCTAssertEqual(next.documentID, report.id)
        XCTAssertTrue(next.response.text.contains("Suggested form"))
        let title = try XCTUnwrap(try PrototypeForm.load().first { $0.id == "kur-reha" }).title
        XCTAssertTrue(next.response.text.contains(title))
        let independent = "I would like to arrange care for my mother"
        XCTAssertNil(DocumentDiscussion.reply(to: independent, state: store.state, language: .en))
        XCTAssertNil(DocumentDiscussion.reply(to: "Was ist der nächste hausarzt", state: store.state, language: .de))
        XCTAssertNil(DocumentDiscussion.reply(to: "Explain football rules", state: store.state, language: .en))
        XCTAssertNil(DocumentDiscussion.reply(to: "When was the World Cup?", state: store.state, language: .en))
        XCTAssertNil(DocumentDiscussion.reply(to: "Was ist ein Befund?", state: store.state, language: .de))
    }

    func testExplanationSharesOnlySourceFindingsAndRetainsNegationAndUncertainty() {
        let source = EvidenceReference(documentID: UUID(), documentTitle: "Local document", locator: "Seite 2",
            quote: "SVNR: 1234567890\nHallo@example.invalid\nFür Erika: Kein Hinweis auf eine frische Fraktur links. Eine Prellung ist möglich.", pageNumber: 2)
        let person = FormPerson(values: ["firstName": "Erika", "insuranceNumber": "1234567890"])
        let review = BefundReview(explanation: "Local summary", passages: [source], actions: [])
        let snippets = DocumentDiscussion.explanationSources(review, people: [person])
        XCTAssertEqual(snippets.map(\.text), ["Für …: Kein Hinweis auf eine frische Fraktur links. Eine Prellung ist möglich."])
        XCTAssertEqual(snippets.first?.evidence, source)
    }

    func testTwoReportsRequireSelectionAndExplicitNewUploadOpensChooser() throws {
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true))
        _ = try store.importText("Befund\nBeurteilung: Beispiel A", title: "A.pdf")
        _ = try store.importText("Befund\nBeurteilung: Beispiel B", title: "B.pdf")
        let reply = try XCTUnwrap(DocumentDiscussion.reply(to: "Erkläre den Befund", state: store.state, language: .de))
        guard case .documents = reply.response.action else { return XCTFail("Ambiguous source must be chosen") }
        XCTAssertNil(reply.documentID)
        let upload = try XCTUnwrap(DocumentDiscussion.reply(to: "Import my vaccination record", state: store.state, language: .en))
        guard case .documents = upload.response.action else { return XCTFail("Expected attachment chooser") }
    }

    func testApplicantReviewsLabeledFieldsBeforeSelectedFormPrefill() throws {
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true))
        let source = try store.importText("""
        Entlassungsbefund
        Vorname: Mira
        Nachname: Muster
        Geburtsdatum: 12.03.1960
        Wohnadresse: Musterstraße 12, 1010 Wien
        Hauptdiagnose: fiktives Beispiel
        Vorname: Andere
        SVNR: 1111111111
        """, title: "Befund")
        let fields = try XCTUnwrap(ReviewedApplicantFields(source))
        XCTAssertNil(store.state.formPeople?.first)
        XCTAssertEqual(fields.person.values["firstName"], "Mira")
        XCTAssertEqual(fields.person.values["postcode"], "1010")
        XCTAssertNil(fields.person.values["insuranceNumber"])
        XCTAssertTrue(fields.evidence.allSatisfy(source.text.contains))
        let person = fields.person
        try store.perform(.savePerson(person))
        let form = try XCTUnwrap(try PrototypeForm.load().first { $0.id == "kur-reha" })
        let draft = form.prefilledDraft(for: person)
        XCTAssertEqual(draft.personID, person.id)
        XCTAssertTrue(draft.values.values.contains("Muster"))
    }

    func testQuestionAboutFluUsesPrintedDiseaseHeadingAndAdministrationDate() throws {
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true))
        let doc = try store.importText("""
        Impfpass
        Influenza (echte Grippe)
        Impfstoff: Beispiel-Impfstoff
        Impfdatum: 02.10.2024
        """, title: "Impfpass")
        let response = DocumentDiscussion.summary(doc, language: .en, state: store.state, question: "When was my flu vaccination?")
        XCTAssertTrue(response.text.contains("02.10.2024"))
        XCTAssertTrue(response.text.contains("Beispiel-Impfstoff"))
    }

    func testScannedImageReturnsReviewableOCRAndPageEvidence() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 420))
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 1000, height: 420))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.black]
            ("Befund" as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: attributes)
            ("Ambulant am 14.10.2024" as NSString).draw(at: CGPoint(x: 50, y: 140), withAttributes: attributes)
            ("Eine ambulante Rehabilitation wird empfohlen." as NSString).draw(at: CGPoint(x: 50, y: 230), withAttributes: attributes)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try XCTUnwrap(image.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let input = try CaseDocumentImport.read(url)
        XCTAssertTrue(input.text.contains("Rehabilitation"))
        XCTAssertNotNil(input.pdf)
        XCTAssertEqual(input.pageSpans?.first?.usedTextRecognition, true)
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true))
        let imported = try store.importChatAttachment(input, title: "Befund.png", language: .en)
        let doc = imported.document
        XCTAssertEqual(imported.addedEventIDs.count, 1)
        let visit = try XCTUnwrap(imported.addedEventIDs.first.flatMap { store.node(id: $0) })
        XCTAssertEqual(visit.evidence.first?.pageNumber, 1)
        XCTAssertTrue(visit.evidence.first?.quote.contains("14.10.2024") == true)
        let action = try XCTUnwrap(BefundReader.review(doc, language: "en")?.actions.first)
        XCTAssertEqual(action.evidence.pageNumber, 1)
        XCTAssertTrue(doc.text.contains(action.evidence.quote))
    }
}
