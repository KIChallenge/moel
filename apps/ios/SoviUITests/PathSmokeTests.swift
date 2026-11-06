import XCTest

@MainActor
final class PathSmokeTests: XCTestCase {
    func testChatTracksAttendanceTasksAndRetainsDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--chat-ui-fixture", "--past-appointment-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let today = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue((today.value as? String ?? "").contains("Still open"))
        let pending = XCTAttachment(screenshot: app.screenshot()); pending.name = "Unrecorded outcomes stay grey"; pending.lifetime = .keepAlways; add(pending)
        app.buttons["path.sovi"].tap()
        let scroll = app.scrollViews["focus.scroll"]
        func reveal(_ element: XCUIElement) {
            for _ in 0..<16 {
                if element.isHittable { return }
                let distance = element.frame.midY - scroll.frame.midY
                let step = min(0.45, max(0.18, abs(distance) / max(1, scroll.frame.height)))
                let startY: CGFloat = distance > 0 ? 0.72 : 0.28
                let endY = startY + (distance > 0 ? -step : step)
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: startY))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: endY))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
            }
            XCTAssertTrue(element.isHittable)
        }
        let quickNo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.checkIn.notAttended.")).firstMatch
        XCTAssertTrue(quickNo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["focus.response"].label.contains("Physiotherapie"))
        XCTAssertTrue(app.staticTexts["focus.response"].label.contains("?"))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.checkIn.")).count, 3)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.timeline.")).firstMatch.exists)
        let field = app.textFields["focus.composer"]
        let editor = field.exists ? field : app.textViews["focus.composer"]
        editor.tap(); editor.typeText("My draft stays here")
        reveal(quickNo); quickNo.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: quickNo)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(editor.value as? String, "My draft stays here")
        app.buttons["focus.close"].tap()
        expectation(for: NSPredicate { _, _ in (today.value as? String ?? "").contains("Missed") }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        let missed = XCTAttachment(screenshot: app.screenshot()); missed.name = "Explicitly missed appointment on red path"; missed.lifetime = .keepAlways; add(missed)
        app.buttons["path.sovi"].tap()
        XCTAssertFalse(quickNo.exists)
        let no = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.entry.notAttended.")).firstMatch
        XCTAssertTrue(no.waitForExistence(timeout: 5)); XCTAssertEqual(no.value as? String, "Selected")
        let yes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.entry.attended.")).firstMatch
        reveal(yes); yes.tap()
        let next = app.buttons["focus.progress"]
        reveal(next); next.tap()
        let done = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.entry.done."))
        XCTAssertTrue(done.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(done.count, 2)
        let notDone = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.entry.notDone.")).firstMatch
        reveal(notDone); notDone.tap()
        expectation(for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: notDone)
        waitForExpectations(timeout: 5)
        for index in 0..<2 {
            let button = done.element(boundBy: index)
            reveal(button); button.tap()
            expectation(for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: button)
            waitForExpectations(timeout: 5)
        }
        XCTAssertEqual(editor.value as? String, "My draft stays here")
        app.buttons["focus.close"].tap()
        expectation(for: NSPredicate { _, _ in (today.value as? String ?? "").contains("Completed") && !(today.value as? String ?? "").contains("Missed") }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        let completed = XCTAttachment(screenshot: app.screenshot()); completed.name = "Completed appointment and tasks on path"; completed.lifetime = .keepAlways; add(completed)
    }

    func testTypedYesRecordsPastAppointmentAndKeepsChatUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--past-appointment-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 10))
        mascot.tap()
        let quickYes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.checkIn.attended.")).firstMatch
        XCTAssertTrue(quickYes.waitForExistence(timeout: 5))
        let nodeID = String(quickYes.identifier.dropFirst("focus.checkIn.attended.".count))
        let field = app.textFields["focus.composer"]
        let editor = field.exists ? field : app.textViews["focus.composer"]
        editor.tap()
        editor.typeText("Yes, I went")
        let send = app.buttons["focus.send"]
        send.tap()

        let recorded = app.buttons["focus.entry.attended." + nodeID]
        expectation(for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: recorded)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.checkIn.")).count, 0)
        editor.tap()
        editor.typeText("My next question")
        XCTAssertEqual(editor.value as? String, "My next question")
        XCTAssertTrue(send.isEnabled)
    }

    func testPostponingPastAppointmentLeavesThePathOpenAndStopsRepeatQuestion() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--past-appointment-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 10))
        mascot.tap()
        let later = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "focus.checkIn.later.")).firstMatch
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        if !later.isHittable { app.scrollViews["focus.scroll"].swipeUp() }
        later.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: later)
        waitForExpectations(timeout: 5)
        app.buttons["focus.close"].tap()
        let today = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue((today.value as? String ?? "").contains("Still open"))
        mascot.tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        XCTAssertFalse(later.exists)
    }

    func testCompactPathColorsAndLatestShortcut() {
        let app = launch(language: "en")
        let today = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "path.day."))
        XCTAssertEqual(entries.count, 15)
        XCTAssertFalse(app.buttons["path.section.context"].exists)
        XCTAssertTrue(app.buttons["path.controls"].isHittable)
        app.buttons["path.controls"].tap()
        XCTAssertTrue(app.buttons["controls.forms"].waitForExistence(timeout: 5))
        app.buttons["sheet.close"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Compact path and navigation"; shot.lifetime = .keepAlways; add(shot)
        revealPath(app.buttons["path.day.day-1993-03-12"], in: app)
        XCTAssertTrue(app.buttons["path.day.day-1993-03-12"].isHittable)
        app.buttons["path.today"].tap()
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: today)
        waitForExpectations(timeout: 5)
        revealPath(app.buttons["path.history.toggle"], in: app); app.buttons["path.history.toggle"].tap()
        XCTAssertEqual(entries.count, 208)
        revealPath(app.buttons["path.history.toggle"], in: app); app.buttons["path.history.toggle"].tap()
        XCTAssertEqual(entries.count, 15)
        XCTAssertTrue(today.isHittable)
    }

    func testNativeStatusBarReturnsToLatestEntry() throws {
        let app = launch(language: "en")
        let today = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        let bar = app.statusBars.firstMatch
        let navigationRight = app.buttons["path.controls"].frame.maxX
        let rail = app.frame.maxX - navigationRight > 40
        if !bar.exists && rail { throw XCTSkip("This simulator exposes a system side rail instead of a tappable status bar.") }
        revealPath(app.buttons["path.day.day-2011-09-01"], in: app)
        if bar.exists { bar.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.035)).tap() }
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: today)
        waitForExpectations(timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "System status bar returns to latest entry"; shot.lifetime = .keepAlways; add(shot)
    }

    func testEnglishRequestOpensGuidedChatOnGermanDevice() {
        let app = launch(language: "de")
        app.buttons["path.sovi"].tap()
        let field = app.textFields["focus.composer"]
        let editor = field.exists ? field : app.textViews["focus.composer"]
        editor.tap()
        editor.typeText("I want to do something for my health.")
        app.buttons["focus.send"].tap()
        let movement = app.buttons["scenario.choice.1"]
        XCTAssertTrue(movement.waitForExistence(timeout: 5))
        XCTAssertEqual(movement.label, "Exercise")
        movement.tap()
        let save = app.buttons["scenario.save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["scenario.saved"].firstMatch.waitForExistence(timeout: 4))
    }

    func testChatFollowUpButtonsRetryAndDraftResume() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--chat-ui-fixture", "-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launch()
        XCTAssertTrue(app.buttons["path.sovi"].waitForExistence(timeout: 10)); app.buttons["path.sovi"].tap()
        let composer = app.textFields["focus.composer"]
        let editor = composer.exists ? composer : app.textViews["focus.composer"]
        editor.tap(); editor.typeText("Ich möchte einen Arzttermin.")
        let send = app.buttons["focus.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let general = app.buttons["chat.general"]
        guard general.waitForExistence(timeout: 5) else {
            let failure = XCTAttachment(screenshot: app.screenshot())
            failure.name = "German message after send failure"; failure.lifetime = .keepAlways; add(failure)
            XCTFail("No first follow-up. Composer: \(editor.value ?? "missing"); send enabled: \(send.isEnabled)")
            return
        }
        XCTAssertTrue(general.isHittable)
        // The padded trailing area must answer too, not just the text itself.
        general.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let insurance = app.buttons["chat.insurance"]
        XCTAssertTrue(insurance.waitForExistence(timeout: 5)); XCTAssertTrue(insurance.isHittable)
        XCTAssertFalse(general.exists)
        insurance.tap()
        XCTAssertTrue(app.buttons["chat.retry"].waitForExistence(timeout: 5))
        XCTAssertFalse(insurance.exists)
        editor.tap(); editor.typeText("Mein Entwurf bleibt hier")
        app.buttons["chat.retry"].tap()
        let reply = app.staticTexts["focus.response"]
        expectation(for: NSPredicate(format: "label == %@", "Danke. Du kannst jetzt weiterschreiben."), evaluatedWith: reply)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(editor.value as? String, "Mein Entwurf bleibt hier")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Chat reply and retained draft"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["focus.close"].tap(); app.buttons["path.sovi"].tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Mein Entwurf bleibt hier")
        XCTAssertEqual(app.staticTexts["focus.response"].label, "Danke. Du kannst jetzt weiterschreiben.")
    }

    func testGroupedPathCardAnchorsToTheButtonAndReturnsToItsEntries() {
        let app = launch(language: "en")
        let today = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(today.label.localizedCaseInsensitiveContains("physio"))
        let anchor = today.frame
        let originalStatus = today.value as? String
        let path = XCTAttachment(screenshot: app.screenshot()); path.name = "Choose bubble above the current day halo"; path.lifetime = .keepAlways; add(path)
        let bubble = today.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -16))
        bubble.tap()
        let card = app.descendants(matching: .any).matching(identifier: "path.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let frame = card.frame
        XCTAssertGreaterThan(frame.width, anchor.width)
        XCTAssertLessThan(frame.width, app.frame.width)
        XCTAssertTrue((frame.minX...frame.maxX).contains(anchor.midX))
        XCTAssertTrue(frame.minY >= anchor.midY || frame.maxY <= anchor.midY)
        let gap = min(abs(frame.minY - anchor.maxY), abs(anchor.minY - frame.maxY))
        XCTAssertLessThan(gap, 60, "The card should meet the selected path button.")
        let rows = card.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "day.entry."))
        XCTAssertEqual(rows.count, 3)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Anchored day card and entry halo"; shot.lifetime = .keepAlways; add(shot)
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["path.card.details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preview.focus"].exists)
        app.buttons["path.card.back"].tap()
        XCTAssertEqual(rows.count, 3)
        rows.matching(NSPredicate(format: "label CONTAINS[c] %@", "Vorsorge")).firstMatch.tap()
        let prepare = app.buttons["preview.preparation"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        prepare.tap()
        XCTAssertTrue(app.textViews["preparation.editor"].waitForExistence(timeout: 5))
        app.buttons["sheet.close"].tap()
        app.buttons["path.card.close"].tap()
        XCTAssertTrue(today.isHittable)
        XCTAssertEqual(today.frame.midY, anchor.midY, accuracy: 3)
        XCTAssertEqual(today.value as? String, originalStatus)
        bubble.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 3)
    }

    func testSingleInformationEntryHasDirectContentAndReadAction() {
        let app = launch()
        let entry = app.buttons["path.day.day-2011-09-01"]
        revealPath(entry, in: app)
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: entry)
        waitForExpectations(timeout: 5)
        let bubble = entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -16))
        bubble.tap()
        let card = app.descendants(matching: .any).matching(identifier: "path.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["path.card.back"].exists)
        XCTAssertTrue(card.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Mitversicherung")).firstMatch.exists)
        let read = app.buttons["preview.read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertTrue(read.label.localizedCaseInsensitiveContains("Als gelesen markieren"),
                      "Opening the Lesen bubble should leave the entry unread.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Information card in its path button color"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let previous = read.label
        read.tap()
        expectation(for: NSPredicate(format: "label != %@", previous), evaluatedWith: read)
        waitForExpectations(timeout: 5)
        app.buttons["path.card.close"].tap()
        entry.tap()
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertNotEqual(read.label, previous)
    }

    func testCardOpensAboveLowerButtonAndDismissesOutside() throws {
        let app = launch()
        revealPath(app.staticTexts["path.planned"], in: app)
        let path = app.scrollViews["path.scroll"]
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "path.day."))
        let viewport = path.frame
        let lowerEntries = entries.allElementsBoundByIndex.filter { entry in
            let frame = entry.frame
            return frame.midY >= viewport.maxY - viewport.height * 0.30 && viewport.contains(frame) && entry.isHittable
        }
        let button = try XCTUnwrap(lowerEntries.last)
        let disk = button.frame
        button.tap()
        let card = app.descendants(matching: .any).matching(identifier: "path.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(card.frame.maxY, disk.minY + 2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Card above a lower path button"
        shot.lifetime = .keepAlways
        add(shot)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: disk.midX, dy: disk.midY)).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: card)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(button.frame.midY, disk.midY, accuracy: 3)
    }

    func testPathSectionsAreReachableAndFocusKeepsPosition() {
        let app = launch()
        let today = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(today.isHittable)
        revealPath(app.buttons["path.day.day-1993-03-12"], in: app)
        XCTAssertTrue(app.staticTexts["path.year-1993"].waitForExistence(timeout: 5))
        let historical = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "path.day.day-1993-")).firstMatch
        XCTAssertTrue(historical.isHittable)
        let historyShot = XCTAttachment(screenshot: app.screenshot()); historyShot.name = "Beginning of the complete history"; historyShot.lifetime = .keepAlways; add(historyShot)
        let oldY = historical.frame.minY
        app.buttons["path.sovi"].tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        let composer = app.textFields["focus.composer"]
        let editor = composer.exists ? composer : app.textViews["focus.composer"]
        editor.tap(); editor.typeText("Entwurf")
        app.buttons["focus.close"].tap()
        XCTAssertTrue(historical.waitForExistence(timeout: 5))
        XCTAssertEqual(historical.frame.minY, oldY, accuracy: 3)
        revealPath(app.staticTexts["path.planned"], in: app)
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
        XCTAssertTrue(app.buttons["form.save"].isHittable); app.buttons["form.save"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Discharge source linked to prefilled rehabilitation form"; shot.lifetime = .keepAlways; add(shot)
    }

    func testWelcomeOffersOptionalCardScanAfterTermsAndResumesManualEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--welcome", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let scan = app.buttons["welcome.scanECard"]
        let hi = app.buttons["welcome.hi"]
        XCTAssertTrue(hi.waitForExistence(timeout: 12))
        XCTAssertFalse(scan.exists)
        hi.tap()
        XCTAssertFalse(scan.exists)
        app.buttons["welcome.accept"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.buttons["welcome.ecard.camera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["welcome.ecard.photo"].exists)
        app.buttons["welcome.ecard.manual"].tap()
        let composer = app.textFields["welcome.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Alex")
        app.buttons["welcome.send"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.exists)
    }

    /// Run on a dedicated simulator seeded only with the two synthetic e-card photos in Fixtures.
    func testWelcomePostsBothECardPhotosAndContinuesWithTheFirstMissingAnswer() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["SOVI_ECARD_PHOTO_QA"] == "1" || environment["TEST_RUNNER_SOVI_ECARD_PHOTO_QA"] == "1",
                          "This UI check needs a simulator photo library seeded with both synthetic card sides.")
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--welcome", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.hi"].waitForExistence(timeout: 15))
        app.buttons["welcome.hi"].tap()
        app.buttons["welcome.accept"].tap()
        app.buttons["welcome.scanECard"].tap()
        let scroll = app.scrollViews["welcome.scroll"]
        func reveal(_ item: XCUIElement) {
            for _ in 0..<8 where !item.isHittable {
                if item.frame.midY < scroll.frame.midY { scroll.swipeDown() } else { scroll.swipeUp() }
            }
            XCTAssertTrue(item.isHittable)
        }
        func choose(_ index: Int) {
            let photo = app.buttons["welcome.ecard.photo"]
            reveal(photo)
            photo.tap()
            let thumbnails = app.images.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@",
                                                              "PXGGridLayout-Info", "Photo,", "Foto,"))
            let item = thumbnails.element(boundBy: index)
            XCTAssertTrue(item.waitForExistence(timeout: 30))
            item.tap()
        }

        let front = app.buttons["welcome.ecard.message.front"]
        let back = app.buttons["welcome.ecard.message.back"]
        var frontIndex = 0
        choose(frontIndex)
        if !front.waitForExistence(timeout: 10) {
            // The system picker can sort by capture date or import time.
            XCTAssertEqual(app.staticTexts["welcome.ecard.error"].label, "That’s the back. Please show me the front first.")
            frontIndex = 1
            choose(frontIndex)
        }
        XCTAssertTrue(front.waitForExistence(timeout: 15))
        XCTAssertFalse(back.exists)
        XCTAssertFalse(app.buttons["welcome.ecard.confirm"].exists)
        reveal(front); front.tap()
        let close = app.buttons["welcome.ecard.preview.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()

        choose(frontIndex)
        let error = app.staticTexts["welcome.ecard.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertEqual(error.label, "That’s the front. I need the back now.")
        XCTAssertFalse(back.exists)
        choose(1 - frontIndex)
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: "welcome.ecard.message.front").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "welcome.ecard.message.back").count, 1)
        let pair = XCTAttachment(screenshot: app.screenshot())
        pair.name = "Two-sided e-card in the welcome conversation"; pair.lifetime = .keepAlways; add(pair)
        let name = app.textFields["welcome.ecard.field.firstName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "ALMA")
        XCTAssertEqual(app.textFields["welcome.ecard.field.lastName"].value as? String, "PROBE")
        XCTAssertEqual(app.textFields["welcome.ecard.field.birthDate"].value as? String, "09.03.1980")
        XCTAssertEqual(app.textFields["welcome.ecard.field.insuranceNumber"].value as? String, "0000000000")
        XCTAssertEqual(app.textFields["welcome.ecard.field.insurer"].value as? String, "ÖGK")
        reveal(name)
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Alina")
        XCTAssertEqual(name.value as? String, "Alina")
        let confirm = app.buttons["welcome.ecard.confirm"]
        reveal(confirm); confirm.tap()
        let skip = app.buttons["welcome.skip"]
        for next in ["Street", "Phone", "Email"] {
            expectation(for: NSPredicate(format: "value == %@", next), evaluatedWith: skip)
            waitForExpectations(timeout: 5)
            skip.tap()
        }
        let location = app.buttons["welcome.skipLocation"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["welcome.location"].label, "Yes, use my location")
        reveal(location); location.tap()
        let reminders = app.buttons["welcome.skipNotifications"]
        XCTAssertTrue(reminders.waitForExistence(timeout: 5))
        reveal(reminders); reminders.tap()
        let review = app.buttons["Review details"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        reveal(review); review.tap()
        XCTAssertEqual(app.textFields["profile.firstName"].value as? String, "Alina")
    }

    func testWelcomeChatResumesAndOffersOptionalPermissions() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--welcome", "-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.hi"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["welcome.composer"].exists)
        app.buttons["welcome.hi"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["welcome.terms"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["welcome.terms"].firstMatch.tap()
        XCTAssertTrue(app.buttons["welcome.terms.close"].waitForExistence(timeout: 5))
        app.buttons["welcome.terms.close"].tap()
        app.buttons["welcome.accept"].tap()
        let composer = app.textFields["welcome.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("Erika")
        XCTAssertTrue(app.buttons["welcome.send"].isEnabled); app.buttons["welcome.send"].tap()
        let skip = app.buttons["welcome.skip"]
        expectation(for: NSPredicate(format: "value == %@", "Nachname"), evaluatedWith: skip)
        waitForExpectations(timeout: 5)
        composer.tap(); composer.typeText("Musterfrau"); app.buttons["welcome.send"].tap()
        XCTAssertTrue(app.buttons["welcome.birthDate"].waitForExistence(timeout: 5))
        XCTAssertFalse(composer.exists)
        app.buttons["welcome.birthDate"].tap()
        XCTAssertTrue(app.buttons["welcome.date.confirm"].waitForExistence(timeout: 5))
        app.buttons["welcome.date.confirm"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("Musterstraße 12, 1010 Wien")
        let addressSend = app.buttons["welcome.send"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: addressSend)
        waitForExpectations(timeout: 5)
        addressSend.tap()
        expectation(for: NSPredicate(format: "value == %@", "Telefon"), evaluatedWith: skip)
        waitForExpectations(timeout: 5)
        composer.tap(); composer.typeText("123")
        XCTAssertFalse(app.buttons["welcome.send"].isEnabled)
        composer.typeText("4567890")
        XCTAssertTrue(app.buttons["welcome.send"].isEnabled); app.buttons["welcome.send"].tap()
        expectation(for: NSPredicate(format: "value == %@", "E-Mail"), evaluatedWith: skip)
        waitForExpectations(timeout: 5)
        composer.tap(); composer.typeText("erika")
        XCTAssertFalse(app.buttons["welcome.send"].isEnabled)
        composer.typeText("@example.invalid")
        XCTAssertTrue(app.buttons["welcome.send"].isEnabled); app.buttons["welcome.send"].tap()
        expectation(for: NSPredicate(format: "value == %@", "Sozialversicherungsnummer"), evaluatedWith: skip)
        waitForExpectations(timeout: 5)
        composer.tap(); composer.typeText("1234567890123")
        expectation(for: NSPredicate(format: "value == %@", "1234567890"), evaluatedWith: composer)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(composer.value as? String, "1234567890")
        XCTAssertLessThan(composer.frame.height, 100)
        let inputShot = XCTAttachment(screenshot: app.screenshot()); inputShot.name = "Welcome ten digit insurance input"; inputShot.lifetime = .keepAlways; add(inputShot)
        app.buttons["welcome.send"].tap()
        skip.tap()
        let location = app.buttons["welcome.location"]
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        XCTAssertEqual(location.label, "Ja, verwende meinen Standort")
        for _ in 0..<4 { if location.isHittable { break }; app.swipeUp() }
        app.buttons["welcome.skipLocation"].tap()
        XCTAssertTrue(app.buttons["welcome.notifications"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["welcome.notifications"].label, "Ja, erinnere mich bitte")
        app.buttons["welcome.skipNotifications"].tap()
        XCTAssertTrue(app.buttons["welcome.done"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Welcome conversation and optional permissions"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["welcome.done"].tap()
        XCTAssertTrue(app.buttons["path.sovi"].waitForExistence(timeout: 5))
        app.buttons["path.sovi"].tap()
        XCTAssertTrue(app.staticTexts["Hi, ich bin Sovi, dein persönlicher Gesundheitsbegleiter."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Erika")).count, 1)

    }

    func testWelcomeMapKitAddressSuggestion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--welcome", "-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.hi"].waitForExistence(timeout: 15)); app.buttons["welcome.hi"].tap()
        app.buttons["welcome.accept"].tap()
        let skip = app.buttons["welcome.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        for _ in 0..<3 { skip.tap() }
        let composer = app.textFields["welcome.composer"]
        composer.tap(); composer.typeText("Josefstädter Straße 1, 1080 Wien")
        let suggestion = app.buttons["welcome.address.0"]
        guard suggestion.waitForExistence(timeout: 15) else {
            throw XCTSkip("Apple Maps suggestions unavailable on this simulator/network; manual address entry is covered separately.")
        }
        XCTAssertTrue(app.staticTexts["Wo wohnst du?"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Live Apple Maps address suggestions"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(suggestion.isHittable); suggestion.tap()
        expectation(for: NSPredicate(format: "value == %@", "Telefon"), evaluatedWith: skip)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.staticTexts["welcome.error"].exists)
    }

    func testWelcomeEnglishLargeTextTermsAndDateControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--welcome", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.hi"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["welcome.hi"].isHittable); app.buttons["welcome.hi"].tap()
        let terms = app.descendants(matching: .any)["welcome.terms"].firstMatch
        for _ in 0..<6 { if terms.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(terms.label, "Terms"); terms.tap()
        XCTAssertTrue(app.buttons["welcome.terms.close"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Readable English terms at largest text size"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["welcome.terms.close"].tap()
        let accept = app.buttons["welcome.accept"]
        for _ in 0..<6 { if accept.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(accept.isHittable); accept.tap()
        let skip = app.buttons["welcome.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5)); skip.tap(); skip.tap()
        XCTAssertTrue(app.buttons["welcome.birthDate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["welcome.composer"].exists)
        let date = XCTAttachment(screenshot: app.screenshot()); date.name = "Welcome date control at largest text size"; date.lifetime = .keepAlways; add(date)
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
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in choice.isHittable }, object: nil)
            guard XCTWaiter.wait(for: [visible], timeout: 3) == .completed else {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Guided follow-up \(answer)"; shot.lifetime = .keepAlways; add(shot)
                XCTFail("A new follow-up should remain visible without hunting through the conversation")
                return
            }
            choice.tap()
        }
        let save = app.buttons["scenario.save"]
        for _ in 0..<8 { if save.isHittable { break }; app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["scenario.saved"].waitForExistence(timeout: 5))
        let forms = app.buttons["case.forms"]
        XCTAssertTrue(forms.waitForExistence(timeout: 5))
        let transcript = app.scrollViews.firstMatch
        for _ in 0..<12 where !forms.isHittable {
            if forms.frame.midY < transcript.frame.midY { transcript.swipeDown() } else { transcript.swipeUp() }
        }
        XCTAssertTrue(forms.isHittable)
        forms.tap()
        XCTAssertTrue(app.navigationBars["Profile und Formulare"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Care demonstration and supplied forms"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["forms.close"].tap()
        XCTAssertTrue(app.buttons["scenario.close"].waitForExistence(timeout: 5)); app.buttons["scenario.close"].tap()
        app.buttons["focus.close"].tap()
        revealPath(app.staticTexts["path.undated"], in: app)
        XCTAssertTrue(app.staticTexts["path.undated"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["path.undated"].isHittable)
        let ownStep = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "path.day.entry-")).firstMatch
        XCTAssertTrue(ownStep.isHittable)
        let ownShot = XCTAttachment(screenshot: app.screenshot()); ownShot.name = "Saved care steps on the path"; ownShot.lifetime = .keepAlways; add(ownShot)
    }

    private func revealPath(_ element: XCUIElement, in app: XCUIApplication) {
        let path = app.scrollViews["path.scroll"]
        XCTAssertTrue(element.waitForExistence(timeout: 6))
        for _ in 0..<18 where !element.isHittable {
            if element.frame.midY < path.frame.midY { path.swipeDown() } else { path.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    func launch(_ largeText: Bool = false, language: String = "de") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_AT"]
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
        XCTAssertEqual(editor.value as? String, "Was ist noch offen?")
        XCTAssertTrue(app.buttons["focus.send"].isEnabled)
        let keyboardShot = XCTAttachment(screenshot: app.screenshot())
        keyboardShot.name = "Sovi Focus with keyboard"; keyboardShot.lifetime = .keepAlways
        add(keyboardShot)
        app.buttons["focus.send"].tap()
        XCTAssertTrue(app.staticTexts["focus.response"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["focus.action"].exists)
        let savedReply = app.staticTexts["focus.response"].label
        editor.tap(); editor.typeText("Ein Entwurf")
        app.buttons["focus.close"].tap()
        XCTAssertTrue(mascot.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0)
        let pathShot = XCTAttachment(screenshot: app.screenshot())
        pathShot.name = "Interactive path"; pathShot.lifetime = .keepAlways
        add(pathShot)
        mascot.tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["focus.response"].label, savedReply)
        XCTAssertEqual(editor.value as? String, "Ein Entwurf")
    }

    func testDoctorSearchNeedsNoConnectionSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--chat-ui-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_AT"]
        app.launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 10)); mascot.tap()
        XCTAssertFalse(app.buttons["chat.settings"].exists)
        XCTAssertEqual(app.secureTextFields.count, 0)
        let field = app.textFields["focus.composer"]
        let editor = field.exists ? field : app.textViews["focus.composer"]
        editor.tap(); editor.typeText("I want to find a doctor")
        app.buttons["focus.send"].tap()
        let firstReply = app.staticTexts["focus.response"]
        XCTAssertTrue(app.buttons["chat.general"].waitForExistence(timeout: 5))
        let initialText = firstReply.label
        app.buttons["chat.general"].tap()
        XCTAssertTrue(app.buttons["chat.insurance"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(firstReply.label, initialText)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Automatic connected chat with a different follow-up"
        shot.lifetime = .keepAlways; add(shot)
    }

    func testPreviewDoesNotCompleteAndLargeTextFocus() {
        let app = launch(true)
        let day = app.buttons["path.day.day-2026-11-05"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        let largePath = XCTAttachment(screenshot: app.screenshot()); largePath.name = "Large text current day"; largePath.lifetime = .keepAlways; add(largePath)
        XCTAssertTrue(day.isHittable)
        day.tap()
        let card = app.descendants(matching: .any).matching(identifier: "path.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(card.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(card.frame.maxX, app.frame.maxX)
        let cardScroll = app.scrollViews["path.card.scroll"]
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "day.entry.")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let focus = app.buttons["preview.focus"]
        for _ in 0..<12 where !focus.isHittable { cardScroll.swipeUp(velocity: .slow) }
        XCTAssertTrue(focus.isHittable)
        let cardShot = XCTAttachment(screenshot: app.screenshot()); cardShot.name = "Large text path card"; cardShot.lifetime = .keepAlways; add(cardShot)
        focus.tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["focus.context"].exists || app.buttons["focus.action"].exists)
        let focusShot = XCTAttachment(screenshot: app.screenshot()); focusShot.name = "Large text focused chat"; focusShot.lifetime = .keepAlways; add(focusShot)
        app.buttons["focus.close"].tap()
        XCTAssertTrue(app.buttons["path.controls"].exists)
    }

    func testCompanionPeeksAtBothEdgesAndKeepsAppointmentContext() {
        let app = launch()
        let mascot = app.buttons["path.sovi"]
        XCTAssertTrue(mascot.waitForExistence(timeout: 10))
        let scroll = app.scrollViews["path.scroll"]
        func expectPlacement(_ value: String) {
            expectation(for: NSPredicate(format: "value == %@ AND hittable == true", value), evaluatedWith: mascot)
            waitForExpectations(timeout: 5)
            XCTAssertEqual(app.buttons.matching(identifier: "path.sovi").count, 1)
        }
        expectPlacement("Auf deinem Weg")
        for _ in 0..<6 {
            if mascot.value as? String == "Am unteren Rand" { break }
            scroll.swipeDown()
        }
        expectPlacement("Am unteren Rand")
        let bottomY = mascot.frame.midY
        XCTAssertLessThan(abs(scroll.frame.maxY - mascot.frame.maxY), 48)
        let bottomShot = XCTAttachment(screenshot: app.screenshot()); bottomShot.name = "Bottom edge companion"; bottomShot.lifetime = .keepAlways; add(bottomShot)
        mascot.tap()
        XCTAssertTrue(app.buttons["focus.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["focus.action"].exists)
        XCTAssertTrue(app.staticTexts["focus.response"].label.contains("Physiotherapie"))
        app.buttons["focus.close"].tap()
        expectPlacement("Am unteren Rand")
        for _ in 0..<12 {
            if mascot.value as? String == "Am oberen Rand" { break }
            scroll.swipeUp()
        }
        expectPlacement("Am oberen Rand")
        XCTAssertLessThan(mascot.frame.midY, bottomY)
        XCTAssertLessThan(abs(scroll.frame.minY - mascot.frame.minY), 48)
        let topShot = XCTAttachment(screenshot: app.screenshot()); topShot.name = "Top edge companion"; topShot.lifetime = .keepAlways; add(topShot)
        app.buttons["path.today"].tap()
        expectPlacement("Auf deinem Weg")
    }

    func testVaccinationDayShowsTwoRecordsAndOriginalPDF() {
        let app = launch()
        let day = app.buttons["path.day.day-2025-11-03"]
        XCTAssertTrue(app.buttons["path.controls"].waitForExistence(timeout: 10))
        for _ in 0..<20 { if day.isHittable { break }; app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(day.isHittable)
        day.tap()
        let covid = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "day.entry.", "COVID-19")).firstMatch
        XCTAssertTrue(covid.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "day.entry.", "Influenza")).firstMatch.exists)
        covid.tap()
        let details = app.buttons["path.card.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        if !details.isHittable { app.scrollViews["path.card.scroll"].swipeUp(velocity: .slow) }
        details.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "vaccination.details", "COMIRNATY LP.8.1 INJ30 10x6")).firstMatch.waitForExistence(timeout: 5))
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
