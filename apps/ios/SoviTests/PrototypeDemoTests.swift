import XCTest
import PDFKit
@testable import Sovi

@MainActor
final class PrototypeDemoTests: XCTestCase {
    func makeStore() throws -> SoviStore { try SoviStore(container: SoviStore.makeContainer(inMemory: true)) }

    func testWelcomeResumesValidatesAndDoesNotSendProfileToChat() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let first = try SoviStore(container: container)
        try first.perform(.startWelcome)
        try first.perform(.answerWelcome("Erika"))
        try first.perform(.answerWelcome("Musterfrau"))
        XCTAssertThrowsError(try first.perform(.answerWelcome("32.13.2020")))
        let second = try SoviStore(container: container)
        XCTAssertEqual(second.state.welcome?.step, 2)
        XCTAssertEqual(second.state.welcome?.history.count, 5)
        XCTAssertEqual(second.state.formPeople?.first?.values["firstName"], "Erika")
        XCTAssertTrue(second.state.conversation.isEmpty)
        try second.perform(.answerWelcome(nil, finish: true))
        XCTAssertTrue(second.state.welcome?.completed == true)
        XCTAssertFalse(second.state.notificationsEnabled)
    }

    func testBothPermissionQuestionsFollowOptionalProfileQuestions() throws {
        let store = try makeStore()
        try store.perform(.startWelcome)
        for _ in WelcomeProgress.fields { try store.perform(.answerWelcome(nil)) }
        XCTAssertTrue(store.state.welcome?.isLocationStep == true)
        try store.perform(.answerWelcome("Ohne Standort weiter"))
        XCTAssertTrue(store.state.welcome?.isNotificationStep == true)
        try store.perform(.answerWelcome("Ohne Erinnerungen weiter"))
        XCTAssertTrue(store.state.welcome?.completed == true)
        XCTAssertFalse(store.state.notificationsEnabled)
    }

    func testRelativeProfileAndFormDraftSurviveRestartAndClearWithDeletion() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let store = try SoviStore(container: container)
        let relative = FormPerson(label: "Mutter", values: ["firstName": "Erika", "lastName": "Musterfrau"])
        try store.perform(.savePerson(relative))
        let draft = SavedFormDraft(formID: "pflegegeld", personID: relative.id, values: ["0:Fam": "Musterfrau"])
        try store.perform(.saveFormDraft(draft.storageKey, draft))
        let reopened = try SoviStore(container: container)
        XCTAssertEqual(reopened.state.formPeople, [relative])
        XCTAssertEqual(reopened.state.formDrafts?[draft.storageKey], draft)
        try reopened.perform(.deleteLocalData)
        XCTAssertNil(reopened.state.formPeople)
        XCTAssertNil(reopened.state.formDrafts)
        XCTAssertNil(reopened.state.welcome)
    }

    func testAllFourJourneysProduceReviewableTasksWithoutBookingsAndStayIdempotent() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let store = try SoviStore(container: container)
        let count = store.nodes.count
        for scenario in DemoScenario.allCases {
            try store.perform(.startScenario(scenario))
            XCTAssertThrowsError(try store.perform(.saveScenarioSteps(scenario)))
            if scenario == .hospital {
                let input = try CaseDocumentImport.read(CaseDocumentImport.sampleURL())
                let document = try store.importText(input.text, title: "Fiktiver Entlassungsbrief", pdfData: input.pdf, pageSpans: input.pageSpans)
                try store.perform(.useCaseDocument(document.id))
                for recommendation in store.state.demoScenarios?["hospital"]?.preparation?.recommendations ?? [] {
                    try store.perform(.reviewCaseRecommendation(recommendation.id, true))
                }
            }
            while let progress = store.state.demoScenarios?[scenario.rawValue], !progress.finished {
                try store.perform(.answerScenario(scenario, try XCTUnwrap(progress.choices.first)))
            }
            if scenario == .care {
                while let progress = store.state.demoScenarios?["care"], let question = progress.preparation?.nextQuestion(for: progress) {
                    try store.perform(.answerCaseQuestion(question.key, question.choices[0].0))
                }
            }
            let before = store.nodes.count
            try store.perform(.saveScenarioSteps(scenario))
            XCTAssertGreaterThan(store.nodes.count, before)
            let after = store.state
            try store.perform(.saveScenarioSteps(scenario))
            XCTAssertEqual(store.state, after)
            let progress = try XCTUnwrap(store.state.demoScenarios?[scenario.rawValue])
            XCTAssertTrue(progress.steps.indices.allSatisfy { store.node(id: progress.taskID($0))?.date == nil })
        }
        XCTAssertGreaterThan(store.nodes.count, count)
        let firstTask = try XCTUnwrap(store.state.demoScenarios?["care"]?.taskID(0))
        try store.perform(.setTask(firstTask, .completed))
        let reopened = try SoviStore(container: container)
        XCTAssertEqual(reopened.node(id: firstTask)?.taskStatus, .completed)
    }

    func testHospitalDoesNotConvertSymptomsIntoRehabilitationRecommendation() throws {
        let progress = DemoScenarioProgress(scenario: .hospital)
        XCTAssertThrowsError(try progress.normalizedAnswer("Meine Schulter tut weh"))
        XCTAssertNoThrow(try progress.normalizedAnswer("Eine ambulante Rehabilitation wird empfohlen."))
        XCTAssertTrue(DemoScenarioProgress.sampleLetter.contains("Fiktiv") || DemoScenarioProgress.sampleLetter.contains("Fictional"))
    }

    func testSevenFormsPrefillOnlySelectedPersonAndExportInteractivePDFs() throws {
        let forms = try PrototypeForm.load()
        XCTAssertEqual(forms.count, 7)
        let person = FormPerson(values: ["firstName": "Erika", "lastName": "Musterfrau", "birthDate": "12.03.1960", "street": "Musterstraße", "house": "12", "postcode": "1010", "city": "Wien", "phone": "+43 1 234567", "email": "erika@example.invalid", "insuranceNumber": "1234120360", "insurer": "ÖGK", "iban": "AT611904300234573201"])
        for form in forms {
            let values = form.prefill(person)
            XCTAssertFalse(values.isEmpty, form.id)
            XCTAssertFalse(values.keys.contains(where: { $0.contains("andere Person") || $0.contains("Versicherte(r)") || $0.contains("Diagnose") || $0.contains("Unterschrift") }), form.id)
            let document = try form.document(values: values)
            for field in form.fields where values[field.id] != nil {
                let annotation = document.page(at: field.page)?.annotations.first { $0.fieldName == field.name }
                XCTAssertEqual(annotation?.widgetStringValue, values[field.id], form.id + ":" + field.name)
            }
            let url = try form.export(values: values)
            let exported = try XCTUnwrap(PDFDocument(url: url))
            XCTAssertEqual(exported.pageCount, form.pages)
            XCTAssertFalse(exported.page(at: 0)?.annotations.isEmpty ?? true)
        }
    }
}
