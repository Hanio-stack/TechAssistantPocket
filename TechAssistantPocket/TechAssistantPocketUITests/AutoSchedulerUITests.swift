import XCTest

final class AutoSchedulerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ flags: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-auto", "--ui-auto-reset", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"] + flags
        app.launch()
        XCTAssertTrue(app.buttons["autoAdd"].waitForExistence(timeout: 15) || app.buttons["saveWorkSettings"].exists)
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func scrollTo(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
            let up = element.exists && element.frame.midY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.65))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.65 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func expectTitle(_ title: String, _ app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: app.staticTexts["proposalTitle"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    @MainActor private func swipe(_ app: XCUIApplication, right: Bool) {
        let title = app.staticTexts["proposalTitle"]
        scrollTo(title, app)
        let y = min(0.7, max(0.3, title.frame.midY / app.frame.height))
        app.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.25 : 0.75, dy: y))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.9 : 0.1, dy: y)), withVelocity: .slow, thenHoldForDuration: 0.2)
    }
    @MainActor private func input(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields[id]
        return field.exists ? field : app.textViews[id]
    }
    @MainActor func testEarlyCompletionSwipeSkipHistoryAndRestart() {
        let app = launch(["--ui-auto-scenario"])
        expectTitle("アニメーション", app)
        XCTAssertFalse(app.staticTexts["180分"].exists)
        XCTAssertEqual(app.staticTexts["proposalGenre"].label, "BK")
        capture(app, "Scheduler — one proposal at 13")
        scrollTo(app.buttons["advanceSchedulerClock"], app); app.buttons["advanceSchedulerClock"].tap()
        expectTitle("アニメーション", app)
        swipe(app, right: true)
        expectTitle("読書", app)
        capture(app, "Scheduler — early completion selects reading at 1520")
        swipe(app, right: false)
        XCTAssertTrue(app.staticTexts["今の空き時間に入るTaskはありません"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(app.buttons["completed-アニメーション"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["backlog-読書"].exists)
        capture(app, "Scheduler — backlog and completed history")
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-auto-reset" }; app.launch()
        XCTAssertTrue(app.staticTexts["今の空き時間に入るTaskはありません"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(app.buttons["completed-アニメーション"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["backlog-アニメーション"].exists)
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["完了 1件"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["スキップ 1件"].exists)
        capture(app, "Scheduler — observed actions survive restart")
    }
    @MainActor func testDateFreeCreationEditingAndGenreReuse() {
        let app = launch(["--ui-auto-empty"])
        app.buttons["autoAdd"].tap()
        let genre = input("genreInput", app); genre.tap(); genre.typeText("  BK  ")
        let title = input("backlogTitleInput", app); title.tap(); title.typeText("敵の攻撃アニメーション")
        app.segmentedControls["backlogPriority"].buttons.element(boundBy: 2).tap()
        XCTAssertEqual(app.datePickers.count, 0)
        XCTAssertEqual(app.pickerWheels.count, 0)
        capture(app, "Scheduler — date-free task entry")
        app.buttons["saveBacklogTask"].tap()
        expectTitle("敵の攻撃アニメーション", app)
        XCTAssertEqual(app.staticTexts["proposalGenre"].label, "BK")
        app.tabBars.buttons["Tasks"].tap()
        let task = app.buttons["backlog-敵の攻撃アニメーション"]
        XCTAssertTrue(task.waitForExistence(timeout: 5)); task.tap()
        let estimate = app.steppers["estimatedMinutes"]
        scrollTo(estimate, app)
        XCTAssertTrue(estimate.label.contains("30分"))
        estimate.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(estimate.label.contains("35分"))
        app.buttons["saveBacklogTask"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "backlog-敵の攻撃アニメーション").count, 1)
        app.buttons["autoAdd"].tap()
        app.buttons["genreHistory"].tap(); app.buttons["BK"].tap()
        let second = input("backlogTitleInput", app); second.tap(); second.typeText("次の制作")
        app.buttons["saveBacklogTask"].tap()
        XCTAssertTrue(app.buttons["backlog-次の制作"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-auto-reset" }; app.launch()
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5)); task.tap()
        scrollTo(app.steppers["estimatedMinutes"], app)
        XCTAssertTrue(app.steppers["estimatedMinutes"].label.contains("35分"))
    }
    @MainActor func testSkipThenCompleteReoffersPreviousTaskWithReduceMotion() {
        let app = launch(["--ui-auto-reduce-motion"])
        swipe(app, right: false); expectTitle("音楽", app)
        swipe(app, right: true); expectTitle("アニメーション", app)
        capture(app, "Scheduler — Reduce Motion and skip re-entry")
    }
    @MainActor func testLongJapaneseAtAccessibilitySize() {
        let app = launch(["--ui-auto-long", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        let title = "ゲームに登場する敵キャラクターの攻撃アニメーションを仕上げる"
        expectTitle(title, app)
        capture(app, "Scheduler — narrow Japanese large genre")
        scrollTo(app.buttons["autoComplete"], app)
        capture(app, "Scheduler — large text reachable actions")
        XCTAssertTrue(app.buttons["autoComplete"].isHittable)
        app.buttons["autoSkip"].tap(); expectTitle("音楽", app)
    }
    @MainActor func testEmptyOutsideNoFitAndCalendarBusy() {
        let cases = [("--ui-auto-empty", "やりたいことを追加しましょう"), ("--ui-auto-outside", "今は作業可能時間の外です"), ("--ui-auto-no-fit", "今の空き時間に入るTaskはありません"), ("--ui-auto-busy", "今はカレンダーの予定があります")]
        for (flag, message) in cases {
            let app = launch([flag]); XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["proposalTitle"].exists); capture(app, "Scheduler — \(flag)"); app.terminate()
        }
    }
    @MainActor func testSetupAndSettingsSurviveRestart() {
        let app = launch(["--ui-auto-setup"])
        XCTAssertTrue(app.navigationBars["Pocketをはじめる"].exists)
        app.buttons["saveWorkSettings"].tap()
        XCTAssertTrue(app.staticTexts["やりたいことを追加しましょう"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-auto-reset" }; app.launch()
        XCTAssertTrue(app.buttons["autoSettings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Pocketをはじめる"].exists)
        app.buttons["autoSettings"].tap()
        XCTAssertTrue(app.staticTexts["21:00"].exists)
        capture(app, "Scheduler — work windows persisted")
    }
}
