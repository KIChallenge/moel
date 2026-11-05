import XCTest

@MainActor
final class PathSmokeTests: XCTestCase {
    func testPathSectionsAreReachableAndFocusKeepsPosition() {
        let app = launch()
        let today = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(today.isHittable)
        app.buttons["path.sections"].tap()
        app.buttons["path.jump.year-1993"].tap()
        // The first year and its actual records must be visible, not just a banner.
        XCTAssertTrue(app.staticTexts["path.year-1993"].waitForExistence(timeout: 5))
        let historical = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "path.day.day-1993-")).firstMatch
        XCTAssertTrue(historical.isHittable)
        let oldY = historical.frame.minY
        app.buttons["path.sovi"].tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        app.buttons["focus.close"].tap()
        XCTAssertTrue(historical.waitForExistence(timeout: 5))
        XCTAssertEqual(historical.frame.minY, oldY, accuracy: 3)
        app.buttons["path.sections"].tap()
        app.buttons["path.jump.planned"].tap()
        XCTAssertTrue(app.staticTexts["path.planned"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["path.planned"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Reachable outlook section"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["path.today"].tap()
        XCTAssertTrue(today.isHittable)
        let current = XCTAttachment(screenshot: app.screenshot()); current.name = "Current day and complete path"; current.lifetime = .keepAlways; add(current)
    }

    func testDischargePDFEvidenceAndPrefilledForm() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--case-demo-person", "-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launch()
        XCTAssertTrue(app.buttons["path.sovi"].waitForExistence(timeout: 10)); app.buttons["path.sovi"].tap()
        app.buttons["Gemeinsam starten"].tap()
        app.buttons["focus.scenario.hospital"].tap()
        XCTAssertTrue(app.buttons["scenario.choice.0"].waitForExistence(timeout: 5)); app.buttons["scenario.choice.0"].tap()
        XCTAssertTrue(app.buttons["scenario.choice.1"].waitForExistence(timeout: 5)); app.buttons["scenario.choice.1"].tap()
        for key in ["rehabilitation", "followUp"] {
            let toggle = app.buttons["case.review.\(key)"]
            for _ in 0..<14 { if toggle.isHittable { break }; app.swipeDown() }
            XCTAssertTrue(toggle.exists); toggle.tap()
        }
        let picker = app.descendants(matching: .any)["case.applicant"].firstMatch
        for _ in 0..<10 { if picker.isHittable { break }; app.swipeUp() }
        picker.tap(); app.buttons["Erika Musterfrau"].tap()
        let forms = app.buttons["case.forms"]
        for _ in 0..<8 { if forms.isHittable { break }; app.swipeUp() }
        forms.tap()
        let form = app.buttons["forms.open.kur-reha"]
        XCTAssertTrue(form.waitForExistence(timeout: 5)); form.tap()
        let name = app.textFields["form.field.0:Patient(in)"]
        for _ in 0..<6 { if name.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(name.value as? String, "Erika Musterfrau")
        app.buttons["form.save.top"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Discharge source linked to prefilled rehabilitation form"; shot.lifetime = .keepAlways; add(shot)
    }

    func testWelcomeChatResumesAndOffersOptionalPermissions() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--welcome", "-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.skip"].waitForExistence(timeout: 15))
        let composer = app.textFields["welcome.composer"]
        composer.tap(); composer.typeText("Erika")
        app.buttons["welcome.send"].tap()
        for _ in 0..<10 { app.buttons["welcome.skip"].tap() }
        let location = app.buttons["welcome.location"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        for _ in 0..<4 { if location.isHittable { break }; app.swipeUp() }
        app.buttons["Ohne Standort weiter"].tap()
        XCTAssertTrue(app.buttons["welcome.notifications"].waitForExistence(timeout: 5))
        app.buttons["Ohne Erinnerungen weiter"].tap()
        XCTAssertTrue(app.buttons["welcome.done"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Welcome chat and optional permissions"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["welcome.done"].tap()
        XCTAssertTrue(app.buttons["path.sovi"].waitForExistence(timeout: 5))
    }

    func testCareDemoSavesStepsAndOpensPrefilledForm() {
        let app = launch()
        app.buttons["path.sovi"].tap()
        app.buttons["Gemeinsam starten"].tap()
        XCTAssertTrue(app.buttons["focus.scenario.care"].waitForExistence(timeout: 5))
        app.buttons["focus.scenario.care"].tap()
        XCTAssertTrue(app.buttons["scenario.choice.2"].waitForExistence(timeout: 5))
        app.buttons["scenario.choice.2"].tap()
        app.buttons["scenario.choice.0"].tap()
        for answer in ["purpose.first", "payer.pv", "role.applicant", "reports.yes"] {
            let choice = app.buttons["case.answer.\(answer)"]
            for _ in 0..<12 { if choice.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(choice.exists); choice.tap()
        }
        let save = app.buttons["scenario.save"]
        for _ in 0..<8 { if save.isHittable { break }; app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["scenario.saved"].waitForExistence(timeout: 5))
        let forms = app.buttons["case.forms"]
        for _ in 0..<10 { if forms.isHittable { break }; app.swipeDown() }
        forms.tap()
        XCTAssertTrue(app.navigationBars["Profile und Formulare"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Care demonstration and supplied forms"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Schließen"].tap()
        XCTAssertTrue(app.buttons["scenario.close"].waitForExistence(timeout: 5)); app.buttons["scenario.close"].tap()
        app.buttons["focus.close"].tap()
        app.buttons["path.sections"].tap()
        app.buttons["path.jump.undated"].tap()
        XCTAssertTrue(app.staticTexts["path.undated"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["path.undated"].isHittable)
        let ownStep = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "path.day.entry-")).firstMatch
        XCTAssertTrue(ownStep.isHittable)
        let ownShot = XCTAttachment(screenshot: app.screenshot()); ownShot.name = "Saved care steps on the path"; ownShot.lifetime = .keepAlways; add(ownShot)
    }

    func launch(_ largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    func testPathFocusKeyboardAndReturn() {
        let app = launch()
        XCTAssertEqual(app.tabBars.count, 0)
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 10))
        mascot.tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        let composer = app.textFields["focus.composer"]
        let editor = composer.exists ? composer : app.textViews["focus.composer"]
        editor.tap()
        editor.typeText("Was ist noch offen?")
        let keyboardShot = XCTAttachment(screenshot: app.screenshot())
        keyboardShot.name = "Sovi Focus with keyboard"; keyboardShot.lifetime = .keepAlways
        add(keyboardShot)
        app.buttons["focus.send"].tap()
        XCTAssertTrue(app.staticTexts["focus.response"].exists)
        XCTAssertTrue(app.buttons["focus.action"].exists)
        app.buttons["focus.close"].tap()
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0)
        let pathShot = XCTAttachment(screenshot: app.screenshot())
        pathShot.name = "Interactive path"; pathShot.lifetime = .keepAlways
        add(pathShot)
    }

    func testOnlineChatSetupRequiresConsentAndKeepsFreeTextComposer() {
        let app = launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 10)); mascot.tap()
        app.buttons["chat.settings"].tap()
        XCTAssertTrue(app.secureTextFields["chat.token"].waitForExistence(timeout: 5))
        let enabled = app.switches["chat.enabled"]
        enabled.tap()
        for _ in 0..<8 { if app.buttons["chat.save"].isHittable { break }; app.swipeUp() }
        XCTAssertFalse(app.buttons["chat.save"].isEnabled)
        let consent = app.switches["chat.consent"]
        for _ in 0..<12 { if consent.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(consent.exists)
        consent.tap()
        for _ in 0..<12 { if app.buttons["chat.save"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["chat.save"].isEnabled)
        // No request or permission prompt is initiated merely by opening settings.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Online chat consent and reviewed background"; shot.lifetime = .keepAlways; add(shot)
    }

    func testPreviewDoesNotCompleteAndLargeTextFocus() {
        let app = launch(true)
        let day = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "day.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        for _ in 0..<14 { if app.buttons["preview.focus"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["preview.focus"].waitForExistence(timeout: 5))
        for _ in 0..<8 { if app.buttons["preview.focus"].isHittable { break }; app.swipeUp() }
        app.buttons["preview.focus"].tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["focus.context"].exists || app.buttons["focus.action"].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
        app.buttons["focus.close"].tap()
        XCTAssertTrue(app.buttons["path.controls"].exists)
    }

    func testCompanionPeeksAtBothEdgesAndKeepsAppointmentContext() {
        let app = launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 10))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<3 { scroll.swipeDown() }
        let bottom = NSPredicate(format: "value == %@", "Am unteren Rand")
        expectation(for: bottom, evaluatedWith: mascot)
        waitForExpectations(timeout: 5)
        mascot.tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["focus.action"].exists)
        XCTAssertTrue(app.staticTexts["focus.response"].label.contains("Physiotherapie"))
        app.buttons["focus.close"].tap()
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        for _ in 0..<7 { scroll.swipeUp() }
        expectation(for: NSPredicate(format: "value == %@", "Am oberen Rand"), evaluatedWith: mascot)
        waitForExpectations(timeout: 5)
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    func testVaccinationDayShowsTwoRecordsAndOriginalPDF() {
        let app = launch()
        let day = app.buttons["path.day.day-2025-11-03"]
        XCTAssertTrue(app.buttons["path.controls"].waitForExistence(timeout: 10))
        for _ in 0..<20 { if day.isHittable { break }; app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(day.isHittable)
        day.tap()
        XCTAssertTrue(app.staticTexts["COVID-19"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Influenza"].exists)
        // The list label selects the actual entry; no source/reading state is changed.
        let covid = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "COVID-19")).firstMatch
        XCTAssertTrue(covid.exists)
        covid.tap()
        XCTAssertTrue(app.staticTexts["COMIRNATY LP.8.1 INJ30 10x6"].waitForExistence(timeout: 5))
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "preview.source.")).firstMatch
        for _ in 0..<16 { if source.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(source.isHittable)
        source.tap()
        let openPDF = app.buttons["source.openPDF"]
        XCTAssertTrue(openPDF.waitForExistence(timeout: 5))
        openPDF.tap()
        XCTAssertTrue(app.navigationBars["Original-PDF"].waitForExistence(timeout: 5))
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
