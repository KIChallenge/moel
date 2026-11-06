import XCTest
import PDFKit
import UIKit
@testable import Sovi

@MainActor
final class PrototypeDemoTests: XCTestCase {
    func makeStore() throws -> SoviStore { try SoviStore(container: SoviStore.makeContainer(inMemory: true)) }

    private func testPhoto(_ side: ECardSide) -> WelcomeECardPhoto {
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16)).jpegData(withCompressionQuality: 0.8) { context in
            (side == .front ? UIColor.green : UIColor.blue).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        }
        return WelcomeECardPhoto(side: side, jpeg: jpeg)
    }

    private func postPair(_ store: SoviStore, front: [PersonField: String], back: [PersonField: String]) throws -> UUID {
        try store.perform(.welcomeECard(.start))
        let id = try XCTUnwrap(store.state.welcome?.eCardScan?.id)
        try store.perform(.welcomeECard(.post(id, testPhoto(.front), front)))
        try store.perform(.welcomeECard(.post(id, testPhoto(.back), back)))
        return id
    }

    func testWelcomeResumesValidatesAndDoesNotSendProfileToChat() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let first = try SoviStore(container: container)
        try first.perform(.startWelcome)
        XCTAssertTrue(first.state.welcome?.isGreetingStep == true)
        XCTAssertThrowsError(try first.perform(.answerWelcome("Erika")))
        try first.perform(.answerWelcome(String(localized: "Hi")))
        XCTAssertTrue(first.state.welcome?.isTermsStep == true)
        XCTAssertThrowsError(try first.perform(.answerWelcome(nil)))
        try first.perform(.answerWelcome(String(localized: "Akzeptieren")))
        try first.perform(.answerWelcome("Erika"))
        try first.perform(.answerWelcome("Musterfrau"))
        XCTAssertThrowsError(try first.perform(.answerWelcome("32.13.2020")))
        let second = try SoviStore(container: container)
        XCTAssertEqual(second.state.welcome?.step, 2)
        XCTAssertEqual(second.state.welcome?.history.count, 10)
        XCTAssertEqual(second.state.welcome?.acceptedTermsVersion, WelcomeProgress.termsVersion)
        XCTAssertNotNil(second.state.welcome?.termsAcceptedAt)
        XCTAssertEqual(second.state.formPeople?.first?.values["firstName"], "Erika")
        XCTAssertTrue(second.state.conversation.isEmpty)
        try second.perform(.answerWelcome(nil, finish: true))
        XCTAssertTrue(second.state.welcome?.completed == true)
        XCTAssertFalse(second.state.notificationsEnabled)
    }

    func testBothPermissionQuestionsFollowOptionalProfileQuestions() throws {
        let store = try makeStore()
        try store.perform(.startWelcome)
        try store.perform(.answerWelcome(String(localized: "Hi")))
        try store.perform(.answerWelcome(String(localized: "Akzeptieren")))
        for _ in WelcomeProgress.fields { try store.perform(.answerWelcome(nil)) }
        XCTAssertTrue(store.state.welcome?.isLocationStep == true)
        try store.perform(.answerWelcome(WelcomeReply.enterPlace.text))
        XCTAssertTrue(store.state.welcome?.isNotificationStep == true)
        try store.perform(.answerWelcome(WelcomeReply.noReminders.text))
        XCTAssertTrue(store.state.welcome?.completed == true)
        XCTAssertFalse(store.state.notificationsEnabled)
        let replies = try XCTUnwrap(store.state.welcome).history.filter { $0.role == "user" }
        XCTAssertEqual(replies.suffix(2).map(\.text), [WelcomeReply.enterPlace.text, WelcomeReply.noReminders.text])
    }

    func testPermissionAnswersKeepTheUsersWordsWhenAccessIsUnavailable() throws {
        for unavailable in [false, true] {
            var person = FormPerson(isSelf: true)
            var welcome = WelcomeProgress(personID: person.id, step: WelcomeProgress.fields.count)
            for (reply, notice) in [
                (WelcomeReply.useLocation, String(localized: "Ich kann deinen Standort gerade nicht verwenden.")),
                (.remindMe, String(localized: "Ich kann dir gerade keine Erinnerungen schicken."))
            ] {
                let previousCount = welcome.history.count
                try welcome.recordAnswer(reply.text, permissionUnavailable: unavailable, person: &person, now: Date())
                let turns = welcome.history.dropFirst(previousCount)
                XCTAssertEqual(turns.map(\.role), unavailable ? ["user", "assistant", "assistant"] : ["user", "assistant"])
                XCTAssertEqual(turns.first?.text, reply.text)
                if unavailable { XCTAssertEqual(turns.dropFirst().first?.text, notice) }
            }
            XCTAssertTrue(welcome.completed)
        }
    }

    func testChatShowsTheAnswerFirstAndTypesOnlyNewReplies() async {
        let history = ChatTurnKey("old question", isUser: false)
        let answer = ChatTurnKey("answer", isUser: true)
        let question = ChatTurnKey("new question", isUser: false)
        let delivery = ChatDelivery()
        delivery.restore([history])
        XCTAssertFalse(delivery.isTyping(ChatTimeline(turns: [history])))
        let waiting = ChatTimeline(turns: [history, answer], awaitingNetwork: true)
        await delivery.present(waiting, reduceMotion: false)
        XCTAssertTrue(delivery.isTyping(waiting))
        XCTAssertEqual(delivery.visible, [history.id, answer.id])
        let received = ChatTimeline(turns: [history, answer, question])
        XCTAssertTrue(delivery.isTyping(received))
        XCTAssertEqual(delivery.writingID(received), question.id)
        await delivery.present(received, reduceMotion: true)
        XCTAssertFalse(delivery.isTyping(received))
        XCTAssertNil(delivery.writingID(received))
        XCTAssertTrue(delivery.visible.contains(question.id))
    }

    func testChatCancelsAnUnshownQuestionAndShowsUrgentRepliesImmediately() async {
        let delivery = ChatDelivery()
        delivery.restore([])
        let question = ChatTimeline(turns: [ChatTurnKey("question", isUser: false)])
        let reveal = Task { await delivery.present(question, reduceMotion: false) }
        await Task.yield()
        reveal.cancel()
        await reveal.value
        XCTAssertTrue(delivery.visible.isEmpty)
        let urgent = ChatTimeline(turns: [ChatTurnKey("urgent", isUser: false)], immediate: true)
        XCTAssertFalse(delivery.isTyping(urgent))
        await delivery.present(urgent, reduceMotion: true)
        XCTAssertEqual(delivery.visible, ["urgent"])
    }

    func testSavedPermissionLabelsReadAsConversationAndKeepTypedAnswers() {
        for language in [ChatLanguage.de, .en] {
            let lookup = language.text
            let now = Date()
            var welcome = WelcomeProgress(personID: UUID())
            welcome.history = [
                .init(role: "assistant", text: lookup("Wie heißt du mit Vornamen?"), date: now),
                .init(role: "user", text: lookup("Standort erlaubt"), date: now),
                .init(role: "assistant", text: lookup("Darf ich deinen Standort nutzen, um Angebote in deiner Nähe zu finden?"), date: now),
                .init(role: "user", text: lookup("Standort erlaubt"), date: now),
                .init(role: "assistant", text: lookup("Darf ich dich an deine Termine und nächsten Schritte erinnern?"), date: now),
                .init(role: "user", text: lookup("Erinnerungen erlaubt"), date: now)
            ]
            let bubbles = welcome.displayHistory
            XCTAssertEqual(bubbles.map(\.id), welcome.history.map(\.id))
            XCTAssertEqual(bubbles[1], welcome.history[1])
            XCTAssertEqual(bubbles[3].text, lookup(WelcomeReply.useLocation.rawValue))
            XCTAssertEqual(bubbles[5].text, lookup(WelcomeReply.remindMe.rawValue))
            XCTAssertEqual(welcome.history[3].text, lookup("Standort erlaubt"))
            welcome.history[3].text = lookup("Standort nicht verfügbar – Ort bei Bedarf eingeben")
            XCTAssertEqual(welcome.displayHistory[3].role, "assistant")
            XCTAssertEqual(welcome.displayHistory[3].text, lookup("Ich kann deinen Standort gerade nicht verwenden."))
        }
    }

    func testReviewedECardPersistsWithoutRepeatingQuestionsOrCopyingPersonalValuesIntoChat() throws {
        let container = try SoviStore.makeContainer(inMemory: true)
        let store = try SoviStore(container: container)
        try store.perform(.startWelcome)
        try store.perform(.answerWelcome(String(localized: "Hi")))
        try store.perform(.answerWelcome(String(localized: "Akzeptieren")))
        let values: [PersonField: String] = [
            .firstName: "Ada", .lastName: "Beispiel", .birthDate: "06.07.1975", .insuranceNumber: "0000000000", .insurer: "ÖGK"
        ]
        try store.perform(.welcomeECard(.start))
        let id = try XCTUnwrap(store.state.welcome?.eCardScan?.id)
        let front = testPhoto(.front), back = testPhoto(.back)
        try store.perform(.welcomeECard(.post(id, front, [.firstName: "Ada", .lastName: "Beispiel", .insuranceNumber: "0000000000"])))
        let resumed = try SoviStore(container: container)
        XCTAssertEqual(resumed.state.welcome?.history.compactMap(\.eCardPhoto), [front])
        XCTAssertEqual(resumed.state.welcome?.eCardScan?.nextSide, .back)
        XCTAssertThrowsError(try resumed.perform(.welcomeECard(.confirm(id, values))))
        try resumed.perform(.welcomeECard(.post(id, back, values)))
        XCTAssertEqual(resumed.state.welcome?.history.compactMap(\.eCardPhoto), [front, back])
        XCTAssertTrue(resumed.state.formPeople?.first?.values.isEmpty == true)
        try resumed.perform(.welcomeECard(.confirm(id, values)))
        let reopened = try SoviStore(container: container)
        let welcome = try XCTUnwrap(reopened.state.welcome)
        let person = try XCTUnwrap(reopened.state.formPeople?.first)
        XCTAssertEqual(welcome.field, .street)
        XCTAssertEqual(welcome.reviewedECardFields, Set(values.keys))
        XCTAssertNil(welcome.eCardScan)
        XCTAssertEqual(welcome.history.filter { $0.role == "user" }.compactMap(\.eCardPhoto), [front, back])
        for (field, value) in values {
            XCTAssertEqual(person.values[field.rawValue], value)
            XCTAssertFalse(welcome.history.contains { $0.text.contains(value) })
        }
        XCTAssertTrue(reopened.state.conversation.isEmpty)
        try reopened.perform(.answerWelcomeAddress(WelcomeAddress(street: "Beispielweg", house: "1", postcode: "1010", city: "Wien")))
        XCTAssertEqual(reopened.state.welcome?.field, .phone)
        try reopened.perform(.answerWelcome(nil))
        XCTAssertEqual(reopened.state.welcome?.field, .email)
        try reopened.perform(.answerWelcome(nil))
        XCTAssertTrue(reopened.state.welcome?.isLocationStep == true)
        try reopened.perform(.answerWelcome(WelcomeReply.enterPlace.text))
        XCTAssertTrue(reopened.state.welcome?.isNotificationStep == true)
        try reopened.perform(.answerWelcome(WelcomeReply.noReminders.text))
        XCTAssertTrue(reopened.state.welcome?.completed == true)
        XCTAssertThrowsError(try reopened.perform(.welcomeECard(.confirm(id, values))))
        try reopened.perform(.deleteLocalData)
        XCTAssertNil(try SoviStore(container: container).state.welcome)
    }

    func testPartialECardKeepsManualAnswersAndOnlySkipsReviewedFields() throws {
        let store = try makeStore()
        try store.perform(.startWelcome)
        try store.perform(.answerWelcome(String(localized: "Hi")))
        try store.perform(.answerWelcome(String(localized: "Akzeptieren")))
        try store.perform(.answerWelcome("Ada"))
        var person = try XCTUnwrap(store.state.formPeople?.first)
        person.values["insurer"] = "Existing"
        try store.perform(.savePerson(person))
        let id = try postPair(store, front: [.firstName: "Ada", .lastName: "Beispiel", .insuranceNumber: "0000000000"],
                              back: [.insuranceNumber: "0000000000"])
        try store.perform(.welcomeECard(.confirm(id, [.firstName: "Another", .lastName: " Beispiel ", .insuranceNumber: "0000000000"])))
        XCTAssertEqual(store.state.formPeople?.first?.values["firstName"], "Ada")
        XCTAssertEqual(store.state.formPeople?.first?.values["lastName"], "Beispiel")
        XCTAssertNil(store.state.formPeople?.first?.values["birthDate"])
        XCTAssertEqual(store.state.welcome?.field, .birthDate)
        for field: PersonField in [.birthDate, .street, .phone, .email] {
            XCTAssertEqual(store.state.welcome?.field, field)
            try store.perform(.answerWelcome(nil))
        }
        XCTAssertEqual(store.state.welcome?.field, .insurer)
        XCTAssertEqual(store.state.formPeople?.first?.values["insurer"], "Existing")
    }

    func testOnlyAcceptedTermsAndValidCardFieldsCanChangeOnboarding() throws {
        let store = try makeStore()
        try store.perform(.startWelcome)
        XCTAssertThrowsError(try store.perform(.welcomeECard(.start)))
        try store.perform(.answerWelcome(String(localized: "Hi")))
        XCTAssertThrowsError(try store.perform(.welcomeECard(.start)))
        try store.perform(.answerWelcome(String(localized: "Akzeptieren")))
        let id = try postPair(store, front: [.firstName: "Ada", .insuranceNumber: "0000000000"],
                              back: [.birthDate: "06.07.1975", .insuranceNumber: "0000000000"])
        let before = store.state
        let invalid: [[PersonField: String]] = [
            [:], [.firstName: "Ada", .phone: "0123456789"], [.firstName: "Ada", .insuranceNumber: "123"],
            [.firstName: "Ada", .birthDate: "31.02.1990"]
        ]
        for values in invalid {
            XCTAssertThrowsError(try store.perform(.welcomeECard(.confirm(id, values))))
            XCTAssertEqual(store.state, before)
        }
    }

    func testMaskedReverseStillAppearsAsAPhotoAndMissingFieldsAreAskedManually() throws {
        let store = try makeStore()
        try store.perform(.startWelcome)
        try store.perform(.answerWelcome(String(localized: "Hi")))
        try store.perform(.answerWelcome(String(localized: "Akzeptieren")))
        let front: [PersonField: String] = [.firstName: "Ada", .lastName: "Beispiel", .insuranceNumber: "0000000000"]
        let id = try postPair(store, front: front, back: [:])
        try store.perform(.welcomeECard(.confirm(id, front)))
        XCTAssertEqual(store.state.welcome?.history.compactMap { $0.eCardPhoto?.side }, [.front, .back])
        XCTAssertEqual(store.state.welcome?.field, .birthDate)
        XCTAssertNil(store.state.formPeople?.first?.values["insurer"])
    }

    func testCardScanKeepsTheFrontWhenTheBackIsRejectedAndDiscardsAnAbandonedPair() throws {
        let store = try makeStore()
        try store.perform(.startWelcome)
        try store.perform(.answerWelcome(String(localized: "Hi")))
        try store.perform(.answerWelcome(String(localized: "Akzeptieren")))
        let original = store.state
        try store.perform(.welcomeECard(.start))
        let id = try XCTUnwrap(store.state.welcome?.eCardScan?.id)
        let front = testPhoto(.front), back = testPhoto(.back)
        let fields: [PersonField: String] = [.firstName: "Ada", .lastName: "Beispiel", .insuranceNumber: "0000000000"]
        XCTAssertThrowsError(try store.perform(.welcomeECard(.post(id, back, fields))))
        try store.perform(.welcomeECard(.post(id, front, fields)))
        let afterFront = store.state
        XCTAssertThrowsError(try store.perform(.welcomeECard(.post(id, front, fields))))
        XCTAssertThrowsError(try store.perform(.welcomeECard(.post(id, back, [.insuranceNumber: "1111111111"]))))
        XCTAssertThrowsError(try store.perform(.answerWelcome("Ada")))
        XCTAssertEqual(store.state, afterFront)
        try store.perform(.welcomeECard(.cancel(id)))
        XCTAssertEqual(store.state, original)
        try store.perform(.welcomeECard(.start))
        XCTAssertThrowsError(try store.perform(.welcomeECard(.post(id, front, fields))))
        XCTAssertTrue(store.state.welcome?.history.compactMap(\.eCardPhoto).isEmpty == true)
        let nextID = try XCTUnwrap(store.state.welcome?.eCardScan?.id)
        try store.perform(.welcomeECard(.post(nextID, front, fields)))
        try store.perform(.answerWelcome(nil, finish: true))
        XCTAssertNil(store.state.welcome?.eCardScan)
        XCTAssertEqual(store.state.welcome?.history.compactMap(\.eCardPhoto), [front])
        XCTAssertTrue(store.state.formPeople?.first?.values.isEmpty == true)
    }

    func testSingleAddressAndContactValidationPreserveFormFields() throws {
        let store = try makeStore()
        try store.perform(.startWelcome)
        try store.perform(.answerWelcome(String(localized: "Hi")))
        try store.perform(.answerWelcome(String(localized: "Akzeptieren")))
        try store.perform(.answerWelcome("Erika"))
        try store.perform(.answerWelcome("Musterfrau"))
        try store.perform(.answerWelcome("12.03.1960"))
        XCTAssertTrue(store.state.welcome?.isAddressStep == true)
        XCTAssertThrowsError(try store.perform(.answerWelcome("Wien")))
        try store.perform(.answerWelcome("Straße des 8. Mai 12a, 1010 Wien"))
        XCTAssertEqual(store.state.formPeople?.first?.values["street"], "Straße des 8. Mai")
        XCTAssertEqual(store.state.formPeople?.first?.values["house"], "12a")
        XCTAssertEqual(store.state.formPeople?.first?.values["postcode"], "1010")
        XCTAssertEqual(store.state.welcome?.field, .phone)
        for bad in ["123", "call me", "+43abc6601234567", "1234567890123456"] {
            XCTAssertThrowsError(try store.perform(.answerWelcome(bad)))
        }
        XCTAssertEqual(store.state.welcome?.field, .phone)
        try store.perform(.answerWelcome("+43 660 1234567"))
        for bad in ["erika", "erika@invalid", "erika..test@example.invalid", "erika@-example.invalid"] {
            XCTAssertThrowsError(try store.perform(.answerWelcome(bad)))
        }
        try store.perform(.answerWelcome("erika+test@example.invalid"))
        XCTAssertThrowsError(try store.perform(.answerWelcome("12345678901")))
        XCTAssertThrowsError(try store.perform(.answerWelcome("123456789a")))
        try store.perform(.answerWelcome("1234567890"))
        XCTAssertFalse(store.state.welcome?.history.contains { $0.text.contains("1234567890") } ?? true)
        XCTAssertEqual(store.state.welcome?.field, .insurer)
        XCTAssertTrue(store.state.conversation.isEmpty)
    }

    func testStructuredAddressAndLegacyWelcomeResume() throws {
        var welcome = WelcomeProgress(personID: UUID(), step: 3)
        var person = FormPerson()
        let address = WelcomeAddress(street: "Musterstraße", house: "12", postcode: "1010", city: "Wien", country: "Österreich")
        try welcome.recordAnswer(address.displayText, address: address, person: &person, now: Date())
        XCTAssertEqual(person.address, "Musterstraße 12, 1010 Wien")
        XCTAssertEqual(person.values["country"], "Österreich")
        XCTAssertEqual(welcome.field, .phone)
        var legacyPerson = FormPerson(isSelf: true)
        let legacy = WelcomeProgress(personID: legacyPerson.id, step: 8, flowVersion: nil)
        var restored = try JSONDecoder().decode(WelcomeProgress.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(restored.field, .email)
        XCTAssertFalse(restored.isLocationStep)
        XCTAssertNil(restored.reviewedECardFields)
        XCTAssertTrue(restored.remainingECardFields(for: legacyPerson).isEmpty)
        XCTAssertNil(restored.eCardScan)
        XCTAssertThrowsError(try restored.handleECard(.start, person: &legacyPerson, now: Date()))
        try restored.recordAnswer(nil, person: &legacyPerson, now: Date())
        XCTAssertEqual(restored.field, .insuranceNumber)
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
        XCTAssertEqual(DemoScenario.matching("Ich möchte für meine Mutter pflegegeld beantragen"), .care)
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
        XCTAssertEqual(try progress.normalizedAnswer(progress.choices[0]), DemoScenarioProgress.sampleLetter)
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
