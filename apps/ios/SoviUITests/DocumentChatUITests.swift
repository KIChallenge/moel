import XCTest

@MainActor
final class DocumentChatUITests: XCTestCase {
    func testPaperclipOpensTheSystemFilePicker() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 12))
        mascot.tap()
        app.buttons["focus.attach"].tap()
        let files = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@",
            ["Browse", "Recents", "On My iPhone", "iCloud Drive"])).firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["documents.report.sample"].exists)
    }

    func testOnlineChatSampleAttachmentShowsLocalReceiptAndOpensDatedPathEvent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--chat-ui-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 12))
        mascot.tap()

        func sendMessage(_ text: String) {
            let field = app.textFields["focus.composer"]
            let editor = field.exists ? field : app.textViews["focus.composer"]
            editor.tap()
            editor.typeText(text)
            app.buttons["focus.send"].tap()
        }
        sendMessage("I want a doctor's appointment.")
        XCTAssertTrue(app.buttons["chat.general"].waitForExistence(timeout: 6))
        app.buttons["focus.more"].tap()
        app.buttons["focus.attachSample"].tap()
        let attachment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.attachment.")).firstMatch
        XCTAssertTrue(attachment.waitForExistence(timeout: 12))
        let event = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.event.")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chat.general"].exists)
        reveal(event, in: app)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Local chat receipt with original attachment and dated life event"
        shot.lifetime = .keepAlways
        add(shot)
        let attachmentID = attachment.identifier
        let eventID = event.identifier
        sendMessage("Which events did you find?")
        let reply = app.staticTexts["focus.response"]
        expectation(for: NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS %@ AND label CONTAINS %@",
                                     "Ultrasound", "14", "2024"), evaluatedWith: reply)
        waitForExpectations(timeout: 5)
        let sameEvent = app.buttons.matching(identifier: eventID)
        XCTAssertEqual(sameEvent.count, 2, "Both the receipt and the follow-up should open the same dated path entry.")
        let followUpEvent = sameEvent.element(boundBy: 1)
        reveal(followUpEvent, in: app)
        followUpEvent.tap()
        let card = app.descendants(matching: .any).matching(identifier: "path.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["path.card.close"].tap()
        XCTAssertTrue(app.buttons["path.day.day-2024-10-14"].isHittable)

        mascot.tap()
        let leaveDocument = app.buttons["focus.document.close"]
        XCTAssertTrue(leaveDocument.waitForExistence(timeout: 5))
        leaveDocument.tap()
        let archive = app.buttons["focus.attachments"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        reveal(archive, in: app)
        archive.tap()
        XCTAssertTrue(app.buttons[attachmentID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[eventID].exists)
        archive.tap()
        XCTAssertFalse(app.buttons[attachmentID].exists)
        sendMessage("I want a doctor's appointment.")
        // The transport fixture returns this choice only on its second request.
        XCTAssertTrue(app.buttons["chat.insurance"].waitForExistence(timeout: 6))
    }

    func testLibraryReportAddsAStepThenExplainsItInChat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 12))
        mascot.tap()
        openLibrary(in: app)
        XCTAssertTrue(app.buttons["documents.report.sample"].waitForExistence(timeout: 5))
        app.buttons["documents.report.sample"].tap()
        XCTAssertTrue(app.staticTexts["documents.explanation"].waitForExistence(timeout: 8))
        let toggle = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "documents.select.")).firstMatch
        reveal(toggle, in: app)
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        let save = app.buttons["documents.apply"]
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["documents.saved"].firstMatch.exists || app.descendants(matching: .any)["documents.saved"].firstMatch.exists)
        let discuss = app.buttons["documents.discuss"]
        reveal(discuss, in: app, up: false)
        discuss.tap()
        let reply = app.descendants(matching: .any).matching(identifier: "focus.response").firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertTrue(reply.label.localizedCaseInsensitiveContains("rehabilitation"))
        XCTAssertTrue(app.buttons["focus.action"].exists)
    }

    func testLibraryReviewAddsSelectedImpfpassRecordToCompactPath() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 12))
        let day = app.buttons["path.day.day-2022-12-04"]
        XCTAssertFalse(day.exists)
        mascot.tap()
        openLibrary(in: app)
        let pass = app.buttons["Impfpass.pdf"]
        XCTAssertTrue(pass.waitForExistence(timeout: 5))
        pass.tap()

        let toggle = app.switches.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "documents.select.", "BA4/5")).firstMatch
        reveal(toggle, in: app)
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        let save = app.buttons["documents.apply"]
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["documents.saved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["sheet.close"].tap()
        app.buttons["focus.close"].tap()

        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["path.day.day-2021-12-09"].exists, "Other vaccine rows were not selected.")
        app.buttons["path.sections"].tap()
        app.buttons["path.jump.year-2022"].tap()
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: day)
        waitForExpectations(timeout: 5)
        day.tap()
        let card = app.descendants(matching: .any).matching(identifier: "path.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "COMIRNATY COV19 BA4/5 10x6")).firstMatch.exists)
        let details = app.buttons["path.card.details"]
        if !details.isHittable { app.scrollViews["path.card.scroll"].swipeUp(velocity: .slow) }
        details.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "vaccination.details", "COMIRNATY COV19 BA4/5 10x6")).firstMatch.waitForExistence(timeout: 5))
    }

    private func openLibrary(in app: XCUIApplication) {
        app.buttons["focus.more"].tap()
        app.buttons["focus.documents"].tap()
    }

    private func reveal(_ item: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<12 where !item.isHittable {
            if up { app.swipeUp() } else { app.swipeDown() }
        }
    }
}
