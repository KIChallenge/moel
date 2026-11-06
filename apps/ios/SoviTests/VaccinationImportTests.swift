import PDFKit
import UIKit
import XCTest
@testable import Sovi

@MainActor
final class VaccinationImportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    func testNativePassImportGroupsActualDatesAndKeepsExactPageEvidenceAfterReload() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let store = try SoviStore(container: container, clock: { self.now })
        try store.perform(.deleteLocalData)
        let url = try XCTUnwrap(VaccinationPassSeed.resourceURL(extension: "pdf"))
        let input = try CaseDocumentImport.read(url)
        let doc = try store.importText(input.text, title: "Upload.pdf", pdfData: input.pdf, pageSpans: input.pageSpans)
        let review = try XCTUnwrap(VaccinationImport.review(doc, calendar: store.state.pathCalendar, asOf: now))
        XCTAssertEqual(review.entries.count, 9)
        XCTAssertEqual(review.unreadableRows, 0)
        XCTAssertNotNil(review.holder)
        XCTAssertEqual(review.entries.filter { $0.record.disease == "COVID-19" }.count, 5)
        XCTAssertEqual(review.entries.filter { !$0.record.hasDocumentedTime }.count, 2)
        XCTAssertTrue(store.state.nodes.isEmpty)
        let ids = Set(review.entries.map(\.id))
        let command = AppCommand.importVaccinations(documentID: doc.id, selectedIDs: ids)
        try store.perform(command)
        try store.perform(command)
        let restored = try SoviStore(container: container, clock: { self.now })
        XCTAssertEqual(restored.state.nodes.count, 9)
        XCTAssertEqual(restored.state.pathDays.count, 8)
        XCTAssertTrue(restored.state.nodes.allSatisfy { $0.kind == .event && $0.appointmentID == nil && $0.scheduleID == nil })
        let record = try XCTUnwrap(restored.state.nodes.first { $0.vaccination?.batch == "V3H731V" })
        XCTAssertEqual(record.date, ISO8601DateFormatter().date(from: "2021-11-17T13:43:00+01:00"))
        XCTAssertEqual(record.vaccination?.doseLabel, "Dosis 1")
        XCTAssertEqual(record.evidence.first?.pageNumber, 2)
        XCTAssertTrue(record.evidence.allSatisfy { doc.text.contains($0.quote) })
        XCTAssertTrue(review.entries.allSatisfy { VaccinationImport.isRecorded($0, in: restored.state, document: doc) })
    }

    func testSuppliedPassReimportPromotesHiddenSeedDayWithoutDuplicatingSeedRecords() throws {
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true), clock: { self.now })
        let baseline = store.state.nodes.count
        let url = try XCTUnwrap(VaccinationPassSeed.resourceURL(extension: "pdf"))
        let input = try CaseDocumentImport.read(url)
        let doc = try store.importText(input.text, title: "My record.pdf", pdfData: input.pdf, pageSpans: input.pageSpans)
        let review = try XCTUnwrap(VaccinationImport.review(doc, calendar: store.state.pathCalendar, asOf: now))
        XCTAssertEqual(doc.id, LifePathSeed.stableID("vaccination-pass-source"))
        let row = try XCTUnwrap(review.entries.first { $0.record.batch == "V3H731V" })
        XCTAssertFalse(store.state.compactPathDays.contains { $0.id == "day-2021-11-17" })
        try store.perform(.importVaccinations(documentID: doc.id, selectedIDs: [row.id]))
        XCTAssertEqual(store.state.nodes.count, baseline)
        XCTAssertTrue(store.state.compactPathDays.contains { $0.id == "day-2021-11-17" })
        XCTAssertTrue(VaccinationImport.isRecorded(row, in: store.state, document: doc))
        XCTAssertEqual(store.state.nodes.filter { $0.vaccination?.importedFromPass == true }.count, 1)
    }

    func testNewPDFEditionRetainsBothPageSourcesAndSeparatesDifferentHolders() throws {
        let store = try SoviStore(container: SoviStore.makeContainer(inMemory: true), clock: { self.now })
        try store.perform(.deleteLocalData)
        let original = try XCTUnwrap(VaccinationPassSeed.resourceURL(extension: "pdf"))
        let originalInput = try CaseDocumentImport.read(original)
        let doc = try store.importText(originalInput.text, title: "Pass.pdf", pdfData: originalInput.pdf, pageSpans: originalInput.pageSpans)
        func lastRow(in source: SourceDocument) throws -> VaccinationCandidate {
            let review = try XCTUnwrap(VaccinationImport.review(source, calendar: store.state.pathCalendar, asOf: now))
            return try XCTUnwrap(review.entries.first { $0.record.batch == "V3H731V" })
        }
        let first = try lastRow(in: doc)
        try store.perform(.importVaccinations(documentID: doc.id, selectedIDs: [first.id]))

        // Insert a new cover into the actual two-page PDF. Its previous second page is now page three.
        let cover = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { context in
            context.beginPage()
            ("Neue Ausfertigung" as NSString).draw(at: CGPoint(x: 16, y: 32), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        let revised = try XCTUnwrap(PDFDocument(url: original))
        let coverDoc = try XCTUnwrap(PDFDocument(data: cover))
        revised.insert(try XCTUnwrap(coverDoc.page(at: 0)), at: 0)
        let reissuedURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: reissuedURL) }
        XCTAssertTrue(revised.write(to: reissuedURL))
        let input = try CaseDocumentImport.read(reissuedURL)
        let secondDoc = try store.importText(input.text, title: "New edition.pdf", pdfData: input.pdf, pageSpans: input.pageSpans)
        XCTAssertNotEqual(secondDoc.id, doc.id)
        let second = try lastRow(in: secondDoc)
        XCTAssertFalse(VaccinationImport.isRecorded(second, in: store.state, document: secondDoc))
        try store.perform(.importVaccinations(documentID: secondDoc.id, selectedIDs: [second.id]))
        try store.perform(.importVaccinations(documentID: secondDoc.id, selectedIDs: [second.id]))
        let nodes = store.state.nodes.filter { $0.vaccination != nil }
        XCTAssertEqual(nodes.count, 1)
        let record = try XCTUnwrap(nodes.first)
        XCTAssertEqual(Set(record.evidence.compactMap(\.pageNumber)), [2, 3])
        XCTAssertEqual(Set(record.evidence.map(\.documentID)), [doc.id, secondDoc.id])

        let otherText = input.text.replacingOccurrences(of: "Testpatient", with: "Different Person")
        let thirdDoc = try store.importText(otherText, title: "Impfpass.txt")
        let third = try lastRow(in: thirdDoc)
        try store.perform(.importVaccinations(documentID: thirdDoc.id, selectedIDs: [third.id]))
        XCTAssertEqual(store.state.nodes.filter { $0.vaccination != nil }.count, 2)
    }

    func testDifferentDocumentAndProductsMissingOrInvalidAdministrationDatesAndSelection() throws {
        let doc = SourceDocument(title: "My Impfpass.txt", text: """
        Person: Fictional Sample
        Tetanus
        Impfstoff: Sample A
        Impfdatum: 17. Jänner 2018
        Eingetragen am: 18. Jänner 2018 um 14:00 Uhr
        Impfstoff: Missing date
        Eingetragen am: 19. Jänner 2018
        Impfstoff: Invalid date
        Impfdatum: 31.02.2019
        Impfstoff: Future date
        Impfdatum: 01.02.2099
        Impfstoff: Sample B
        Impfdatum: 06.05.2020 um 10:28 Uhr (UTC+2)
        Empfohlene Impfungen
        Impfstoff: Suggested
        Impfdatum: 01.01.2020
        """)
        var state = AppState(documents: [doc], fixtureTimeZoneIdentifier: "Pacific/Honolulu")
        let review = try XCTUnwrap(VaccinationImport.review(doc, calendar: state.pathCalendar, asOf: now))
        XCTAssertEqual(review.entries.map(\.record.product), ["Sample A", "Sample B"])
        XCTAssertEqual(review.unreadableRows, 3)
        let row = try XCTUnwrap(review.entries.last)
        XCTAssertNil(row.evidence.pageNumber)
        XCTAssertTrue(doc.text.contains(row.evidence.quote))
        XCTAssertThrowsError(try VaccinationImport.apply(documentID: doc.id, selectedIDs: [row.id, UUID()], to: &state, now: now))
        XCTAssertTrue(state.nodes.isEmpty)
        try VaccinationImport.apply(documentID: doc.id, selectedIDs: [row.id], to: &state, now: now)
        XCTAssertEqual(state.nodes.map(\.vaccination?.product), ["Sample B"])
        XCTAssertEqual(state.nodes.first?.date, ISO8601DateFormatter().date(from: "2020-05-06T08:28:00Z"))
        XCTAssertEqual(state.pathDays.map(\.id), ["day-2020-05-06"])
        XCTAssertTrue(state.formPeople?.isEmpty != false)
    }
}
