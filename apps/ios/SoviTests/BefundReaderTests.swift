import XCTest
@testable import Sovi

@MainActor
final class BefundReaderTests: XCTestCase {
    private let careReport = """
    Entlassungsbefund
    Zusammenfassende Beurteilung
    Die Patientin kehrt mit Unterstützung nach Hause zurück.

    Offene Aufgaben nach der Entlassung
    Termin zur hausärztlichen Kontrolle
    vereinbaren am 18.11.2026
    Vertrauensperson
    Rehabilitationsantrag vorbereiten Behandelnde Ärztin
    Mobile Hauskrankenpflege organisieren Sozialberatung
    """
    private func document(_ text: String) -> SourceDocument {
        SourceDocument(title: "Befund", text: text, pageSpans: [
            DocumentPageSpan(pageNumber: 2, utf16Start: 0, utf16Length: (text as NSString).length)
        ])
    }

    func testLifeEventsUseEncounterDayInsteadOfReportOrRegistrationDates() throws {
        let doc = document("""
        US-Befund
        vom 6. August 2023 um 04:46 Uhr | Version: 1
        Ambulant am 2. August 2023 FZ: 987
        Ambulant am 2. August 2023 von 09:43 Uhr bis 10:56 Uhr
        Befund
        Der Untersuchungsbericht liegt vor.
        Empfehlungen
        Untersuchungsdatum: 18. August 2023
        """)
        let calendar = AppState().pathCalendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6)))
        let items = BefundReader.lifeEvents(in: doc, calendar: calendar, asOf: now, language: "en")
        XCTAssertEqual(items.count, 1)
        let event = try XCTUnwrap(items.first)
        XCTAssertEqual(event.title, "Outpatient visit · Ultrasound report")
        XCTAssertEqual(event.date, calendar.date(from: DateComponents(year: 2023, month: 8, day: 2)))
        XCTAssertEqual(event.evidence.quote, "Ambulant am 2. August 2023")
        XCTAssertEqual(event.evidence.pageNumber, 2)
        XCTAssertEqual(event.evidence.documentID, doc.id)
        XCTAssertEqual(event.modalityEvidence.map(\.quote), ["US-Befund"])
        XCTAssertEqual(event.modalityEvidence.first?.pageNumber, 2)
        let german = try XCTUnwrap(BefundReader.lifeEvents(in: doc, calendar: calendar, asOf: now, language: "de").first)
        XCTAssertEqual(event.id, german.id)
        XCTAssertEqual(event.evidence, german.evidence)
        XCTAssertEqual(german.title, "Ambulanter Besuch · Ultraschallbefund")
    }

    func testEncounterModalityUsesReportContentAndKeepsOneVisitForCombinedImaging() throws {
        let calendar = AppState().pathCalendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6)))
        let text = """
        Befund Bildgebende Diagnostik
        Ambulant am 14. Oktober 2024
        Befund
        /d

        Weichteilsonographie des linken Arms
        Befundtext.
        Schlagwörter (Services) Röntgen.beidseits.unbestimmt.Hand
        """
        let doc = document(text)
        let visits = BefundReader.lifeEvents(in: doc, calendar: calendar, asOf: now, language: "en")
        XCTAssertEqual(visits.map(\.title), ["Outpatient visit · X-ray and ultrasound report"])
        let visit = try XCTUnwrap(visits.first)
        XCTAssertEqual(visit.date, calendar.date(from: DateComponents(year: 2024, month: 10, day: 14)))
        XCTAssertEqual(visit.modalityEvidence.count, 2)
        XCTAssertTrue(visit.modalityEvidence.allSatisfy { text.contains($0.quote) && $0.pageNumber == 2 })
        let ambiguous = SourceDocument(title: "Röntgen Befund", text: """
        Befund Bildgebende Diagnostik
        Ambulant am 14. Oktober 2024
        Empfehlungen
        Sonographie des linken Arms
        Bitte mit der Praxis besprechen.
        """)
        let unspecified = try XCTUnwrap(BefundReader.lifeEvents(in: ambiguous, calendar: calendar, asOf: now, language: "en").first)
        XCTAssertEqual(unspecified.title, "Outpatient visit")
        XCTAssertTrue(unspecified.modalityEvidence.isEmpty)
    }

    func testDischargeReportOnlyEmitsExplicitValidPastHeaderDates() throws {
        let calendar = AppState().pathCalendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6)))
        let doc = SourceDocument(title: "Krankenhaus-Entlassungsbefund", text: """
        Geburtsdatum 01.01.1970
        Aufnahmedatum: 12.10.2026
        Entlassungsdatum
        29.10.2026
        Untersuchungsdatum: 31.02.2026
        2. Aufnahmediagnosen und medizinische Vorgeschichte
        Untersuchungsdatum: 20.04.2025
        """)
        let events = BefundReader.lifeEvents(in: doc, calendar: calendar, asOf: now, language: "en")
        XCTAssertEqual(events.map(\.title), ["Hospital admission", "Hospital discharge"])
        XCTAssertEqual(events.map(\.evidence.quote), ["Aufnahmedatum: 12.10.2026", "Entlassungsdatum\n29.10.2026"])
        XCTAssertTrue(events.allSatisfy { $0.evidence.pageNumber == nil })
        for text in ["Entlassungsdatum 07.11.2026", "Entlassungsdatum 01.11.2026 (vorläufig)",
                     "Entlassungsdatum 01.11.2026 oder 02.11.2026",
                     "Entlassungsdatum 01.11.2026\nEntlassungsdatum 02.11.2026",
                     "Aufnahmedatum 03.11.2026\nEntlassungsdatum 01.11.2026",
                     "Geplante Untersuchungen\nUntersuchungsdatum 01.11.2026",
                     "Geburtsdatum 01.01.1970\nvom 3. März 2020 um 15:00 Uhr"] {
            let report = SourceDocument(title: "Entlassungsbefund", text: text)
            XCTAssertTrue(BefundReader.lifeEvents(in: report, calendar: calendar, asOf: now, language: "de").isEmpty, text)
        }
        let unknown = SourceDocument(title: "Notizen", text: "Entlassungsdatum 29.10.2026")
        XCTAssertTrue(BefundReader.lifeEvents(in: unknown, calendar: calendar, asOf: now, language: "de").isEmpty)
    }

    func testReportProducesReviewedDatedAndUndatedTasksWithSourceEvidence() throws {
        let doc = document(careReport)
        let review = try XCTUnwrap(BefundReader.review(doc, language: "en"))
        XCTAssertEqual(review.actions.count, 3)
        XCTAssertEqual(review.passages.first?.quote, "Die Patientin kehrt mit Unterstützung nach Hause zurück.")
        XCTAssertTrue(review.actions.allSatisfy { doc.text.contains($0.evidence.quote) && $0.evidence.pageNumber == 2 })
        let followUp = try XCTUnwrap(review.actions.first { $0.caseKind == .followUp })
        let reha = try XCTUnwrap(review.actions.first { $0.caseKind == .rehabilitation })
        XCTAssertEqual(reha.formID, "kur-reha")
        XCTAssertNil(reha.date)
        var state = AppState()
        state.documents = [doc]
        XCTAssertThrowsError(try BefundReader.apply(documentID: doc.id, selectedIDs: [followUp.id, UUID()], language: "en", to: &state, now: Date()))
        XCTAssertTrue(state.nodes.isEmpty)
        try BefundReader.apply(documentID: doc.id, selectedIDs: [followUp.id], language: "en", to: &state, now: Date())
        let node = try XCTUnwrap(state.nodes.first)
        XCTAssertEqual(node.kind, .task)
        let date = try XCTUnwrap(node.date)
        let parts = state.pathCalendar.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 18)
        XCTAssertEqual(node.evidence, [followUp.evidence])
        state.nodes[0].taskStatus = .completed
        let saved = state
        try BefundReader.apply(documentID: doc.id, selectedIDs: [followUp.id], language: "tr", to: &state, now: Date())
        XCTAssertEqual(state, saved)
        XCTAssertTrue(BefundReader.isAdopted(followUp, in: state))
    }

    func testReportsExplainFindingsInFourLanguagesAndPreserveNegationAndHistory() throws {
        let doc = document("""
        US-Befund
        Anamnese
        Please schedule a follow-up appointment.
        Befund
        Das Team beschreibt eine subkutane Veränderung. Keine ärztliche Nachkontrolle wird empfohlen.
        Allgemeine Daten
        Ort: Beispielstadt.
        """)
        for (language, expected) in [("de", "unter der Haut"), ("en", "beneath the skin"), ("ar", "تحت الجلد"), ("tr", "deri altında")] {
            let review = try XCTUnwrap(BefundReader.review(doc, language: language))
            XCTAssertTrue(review.explanation.contains(expected), language)
            XCTAssertFalse(review.explanation.contains("Beispielstadt"))
            XCTAssertTrue(review.actions.isEmpty)
            XCTAssertTrue(review.passages.allSatisfy { doc.text.contains($0.quote) })
        }
        let unrelated = SourceDocument(title: "Einkauf", text: "Please schedule a follow-up appointment.")
        XCTAssertNil(BefundReader.review(unrelated, language: "en"))
    }

    func testUnfamiliarFindingsPreserveTheReportAuthorsUncertaintyAndLaterality() throws {
        let text = "Röntgenbefund\nBeurteilung: Kein Hinweis auf eine Fraktur am rechten Handgelenk. Ein kleines Hämatom am linken Unterarm ist nicht sicher ausgeschlossen."
        let review = try XCTUnwrap(BefundReader.review(SourceDocument(title: "Befund", text: text), language: "en"))
        XCTAssertTrue(review.explanation.contains("leave that question open"))
        XCTAssertTrue(review.explanation.contains("what the authors did not find"))
        XCTAssertTrue(review.explanation.contains("a broken bone"))
        XCTAssertTrue(review.explanation.contains("rechten Handgelenk"))
        XCTAssertTrue(review.explanation.contains("linken Unterarm"))
        XCTAssertTrue(review.actions.isEmpty)
        let freeText = "Die Untersuchung ergab keinen Hinweis auf eine Fraktur am rechten Unterarm."
        let freeReview = try XCTUnwrap(BefundReader.review(SourceDocument(title: "Befund", text: freeText), language: "en"))
        XCTAssertEqual(freeReview.passages.first?.quote, freeText)
        XCTAssertTrue(freeReview.explanation.contains("broken bone"))
        let unsupported = try XCTUnwrap(BefundReader.review(SourceDocument(title: "Befund", text: "Metadaten der Untersuchung."), language: "en"))
        XCTAssertTrue(unsupported.explanation.contains("original"))
        XCTAssertTrue(unsupported.passages.isEmpty)
    }

    func testFlexibleAppointmentRequestsIncludeProviderAndDateWithoutInferringFromOtherDates() throws {
        let doc = SourceDocument(title: "Arztbrief", text: """
        Befund vom 02.02.2025
        Bitte vereinbaren Sie bis zum 18.11.2026 einen Kontrolltermin bei der Fachambulanz.
        Bitte bringen Sie den Überweisungsschein zum Termin mit.
        """)
        let review = try XCTUnwrap(BefundReader.review(doc, language: "en"))
        XCTAssertEqual(review.actions.count, 2)
        let booking = try XCTUnwrap(review.actions.first { $0.caseKind == .followUp })
        XCTAssertTrue(booking.evidence.quote.contains("Fachambulanz"))
        XCTAssertTrue(booking.evidence.quote.contains("18.11.2026"))
        XCTAssertNotNil(booking.date)
        XCTAssertNil(booking.evidence.pageNumber)
        XCTAssertNil(review.actions.first(where: { $0.id != booking.id })?.date)
        let alternatives = SourceDocument(title: "Befund", text: "Nachkontrolle vereinbaren am 12.12.2026 oder am 14.12.2026.")
        let open = try XCTUnwrap(BefundReader.review(alternatives, language: "de")?.actions.first)
        XCTAssertTrue(open.evidence.quote.contains("14.12.2026"))
        XCTAssertNil(open.date)
        let negative = SourceDocument(title: "Befund", text: "Please do not schedule a follow-up appointment.\nEine ambulante Rehabilitation wird empfohlen, wenn die Praxis dies bestätigt.")
        XCTAssertTrue(try XCTUnwrap(BefundReader.review(negative, language: "en")).actions.isEmpty)
    }

    func testAttachmentAndHospitalCaseUseOnePersistentTask() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let store = try SoviStore(container: container)
        let doc = try store.importText(careReport, title: "Entlassungsbefund")
        let review = try XCTUnwrap(BefundReader.review(doc, language: "de"))
        let action = try XCTUnwrap(review.actions.first { $0.caseKind == .rehabilitation })
        try store.perform(.adoptBefundActions(documentID: doc.id, selectedIDs: [action.id], language: "de"))
        try store.perform(.setTask(action.id, .completed))
        try store.perform(.useCaseDocument(doc.id))
        let caseItem = try XCTUnwrap(store.state.demoScenarios?["hospital"]?.preparation?.recommendations.first { $0.kind == .rehabilitation })
        try store.perform(.reviewCaseRecommendation(caseItem.id, true))
        try store.perform(.answerScenario(.hospital, String(localized: "Vormittags")))
        try store.perform(.saveScenarioSteps(.hospital))
        let reopened = try SoviStore(container: container)
        XCTAssertEqual(reopened.nodes.filter { $0.id == action.id }.count, 1)
        XCTAssertEqual(reopened.node(id: action.id)?.taskStatus, .completed)
        XCTAssertTrue(BefundReader.isAdopted(action, in: reopened.state))
        let state = reopened.state
        try reopened.perform(.adoptBefundActions(documentID: doc.id, selectedIDs: [action.id], language: "en"))
        XCTAssertEqual(state, reopened.state)
    }
}
