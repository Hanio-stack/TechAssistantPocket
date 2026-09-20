import XCTest

final class TechAssistantPocketUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(seed: Bool = false, largeText: Bool = false, denied: Bool = false) -> XCUIApplication {
        // Launch smoke tests also exercise landscape; each interaction test starts in portrait.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if denied { app.launchArguments.append("--ui-denied") }
        if seed { app.launchArguments.append("--ui-seed") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Tasks"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func screenshot(_ app: XCUIApplication, name: String) {
        // XCTest can report idle before a navigation transition's final rendered frame.
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected the item to be reachable by scrolling")
    }

    @MainActor func testTaskCreateEditScheduleExecuteAndArchive() {
        let app = launch()
        app.tabBars.buttons["Tasks"].tap()
        app.buttons["globalAdd"].tap()
        app.buttons["Task を追加"].tap()
        let title = app.textFields["taskTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("読書")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["読書"].waitForExistence(timeout: 5))
        app.buttons["読書"].tap()
        app.buttons["編集"].tap()
        title.tap(); title.typeText("を続ける")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.navigationBars["読書を続ける"].waitForExistence(timeout: 5))
        app.buttons["予定なしの実行を記録"].tap()
        app.buttons["記録"].tap()
        XCTAssertTrue(app.staticTexts["予定なしの実行"].waitForExistence(timeout: 5))
        app.buttons["予定を追加"].tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["未確定"].waitForExistence(timeout: 5))
        screenshot(app, name: "Task detail — Japanese")
        app.staticTexts["未確定"].firstMatch.tap()
        app.buttons["実行を記録"].tap()
        app.buttons["記録"].tap()
        XCTAssertTrue(app.staticTexts["予定枠ではできなかった"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Task を削除"].tap()
        app.buttons["削除する"].tap()
        XCTAssertTrue(app.staticTexts["やりたいことを追加"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["読書を続ける"].waitForExistence(timeout: 5))
        screenshot(app, name: "Archived history in Insights")
    }

    @MainActor func testTodayReviewInsightsAndOrdinaryEvent() {
        let app = launch(seed: true)
        XCTAssertTrue(app.staticTexts["友達と昼食"].waitForExistence(timeout: 5))
        screenshot(app, name: "Today — Tasks and ordinary Event")
        app.swipeUp()
        XCTAssertTrue(app.buttons["reviewCTA"].waitForExistence(timeout: 5))
        app.buttons["reviewCTA"].tap()
        XCTAssertTrue(app.navigationBars["一日を振り返る"].waitForExistence(timeout: 5))
        screenshot(app, name: "Review — Japanese")
        if app.staticTexts["未確定"].exists {
            let missed = app.buttons["できなかった"]
            for _ in 0..<4 where !missed.isHittable { app.swipeUp() }
            XCTAssertTrue(missed.isHittable)
            missed.tap()
        }
        let finishReview = app.buttons["finishReview"]
        for _ in 0..<4 where !finishReview.isHittable { app.swipeUp() }
        XCTAssertTrue(finishReview.isHittable)
        XCTAssertTrue(finishReview.isEnabled)
        finishReview.tap()
        app.tabBars.buttons["Insights"].tap()
        screenshot(app, name: "Insights — weekly success rate")
        let taskInsight = app.staticTexts["英語学習と長い日本語タイトルの表示確認"]
        scrollTo(taskInsight, in: app)
        taskInsight.tap()
        screenshot(app, name: "Task insight — weekdays")
        scrollTo(app.buttons["この時間に変更する"], in: app)
        screenshot(app, name: "Task insight — suggestion")
        app.buttons["この時間に変更する"].tap()
        app.buttons["キャンセル"].tap() // A proposal never changes the schedule without confirmation.
        XCTAssertTrue(app.buttons["この時間に変更する"].exists)
        let proposedDate = app.staticTexts["suggestionDate"].label
        app.buttons["この時間に変更する"].tap()
        app.alerts.buttons["この時間に変更する"].tap()
        // Another pending occurrence may receive a different proposal after this one is applied.
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let date = app.staticTexts["suggestionDate"]
            return !date.exists || date.label != proposedDate
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 5), .completed)
        screenshot(app, name: "Suggestion — explicitly approved")
        app.tabBars.buttons["Today"].tap()
        app.buttons["globalAdd"].tap()
        app.buttons["予定を追加"].tap()
        let title = app.textFields["eventTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("美容院")
        screenshot(app, name: "Ordinary Event editor")
        app.buttons["saveEvent"].tap()
        app.swipeDown(); app.swipeDown()
        scrollTo(app.staticTexts["美容院"], in: app)
        screenshot(app, name: "Today — new ordinary Event")
    }

    @MainActor func testJapaneseLargeTextNavigation() {
        let app = launch(seed: true, largeText: true)
        screenshot(app, name: "Today — accessibility text")
        app.tabBars.buttons["Tasks"].tap()
        screenshot(app, name: "Tasks — accessibility text")
        app.tabBars.buttons["Insights"].tap()
        screenshot(app, name: "Insights — accessibility text")
        XCTAssertTrue(app.staticTexts["今週の成功率"].exists)
    }
    @MainActor func testCalendarDeniedStillAllowsTasks() {
        let app = launch(denied: true)
        app.tabBars.buttons["Tasks"].tap()
        app.buttons["globalAdd"].tap()
        app.buttons["Task を追加"].tap()
        let title = app.textFields["taskTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("連携なしTask")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["連携なしTask"].waitForExistence(timeout: 5))
        app.buttons["globalAdd"].tap()
        app.buttons["予定を追加"].tap()
        XCTAssertTrue(app.staticTexts["calendarDeniedHelp"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveEvent"].isEnabled)
        screenshot(app, name: "Calendar denied — ordinary Event guidance")
    }

}
