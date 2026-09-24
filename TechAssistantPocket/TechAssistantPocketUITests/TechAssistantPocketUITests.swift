import XCTest

final class TechAssistantPocketUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(seed: Bool = false, largeText: Bool = false, denied: Bool = false,
                                   todayFocus: Bool = false, noCurrent: Bool = false) -> XCUIApplication {
        // Launch smoke tests also exercise landscape; each interaction test starts in portrait.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if denied { app.launchArguments.append("--ui-denied") }
        if seed { app.launchArguments.append("--ui-seed") }
        if todayFocus { app.launchArguments.append("--ui-today-focus") }
        if noCurrent { app.launchArguments.append("--ui-no-current") }
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
        for _ in 0..<12 where !element.isHittable {
            let moveDown = element.exists && element.frame.midY < app.frame.midY
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.35 : 0.65))
            let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.65 : 0.35))
            origin.press(forDuration: 0.05, thenDragTo: target)
        }
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
        if !app.staticTexts["友達と昼食"].exists {
            scrollTo(app.buttons["todayHistory"], in: app)
            app.buttons["todayHistory"].tap()
        }
        scrollTo(app.staticTexts["友達と昼食"], in: app)
        screenshot(app, name: "Today — Tasks and ordinary Event")
        scrollTo(app.buttons["reviewCTA"], in: app)
        app.buttons["reviewCTA"].tap()
        XCTAssertTrue(app.navigationBars["一日を振り返る"].waitForExistence(timeout: 5))
        screenshot(app, name: "Review — Japanese")
        if app.buttons["できなかった"].exists {
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
        let tasksTab = app.tabBars.buttons["Tasks"]
        XCTAssertTrue(tasksTab.waitForExistence(timeout: 5))
        tasksTab.tap()
        screenshot(app, name: "Calendar denied — Tasks tab selection")
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: tasksTab)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
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

    @MainActor private func assertCentralFocus(_ title: String, in app: XCUIApplication) {
        let focus = app.buttons["todayFocus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        XCTAssertTrue(focus.label.contains(title))
        let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let ratio = focus.frame.midY / app.frame.height
            return focus.isHittable && ratio > 0.25 && ratio < 0.7
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 5), .completed)
    }

    @MainActor func testTodayFocusAndHistory() {
        let app = launch(todayFocus: true)
        XCTAssertTrue(app.staticTexts["currentTaskTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["currentTaskTitle"].label, "16時のTask")
        XCTAssertTrue(app.buttons["skipCurrentTask"].isHittable)
        XCTAssertTrue(app.buttons["completeCurrentTask"].isHittable)
        XCTAssertFalse(app.buttons["一時停止"].exists)
        XCTAssertFalse(app.textFields["メモ"].exists)
        XCTAssertFalse(app.staticTexts["敬老の日"].exists)
        XCTAssertTrue(app.staticTexts["自分の終日予定"].exists)
        XCTAssertFalse(app.staticTexts["完了したTask6"].exists)
        XCTAssertFalse(app.staticTexts["12時に終了した予定"].exists)
        screenshot(app, name: "Today — current task with collapsed history")

        app.buttons["completeCurrentTask"].tap()
        app.buttons["記録"].tap()
        if !app.buttons["todayFocus"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        assertCentralFocus("17時のTask", in: app)
        screenshot(app, name: "Today — focus moves after completion")

        scrollTo(app.buttons["todayHistory"], in: app)
        app.buttons["todayHistory"].tap()
        scrollTo(app.staticTexts["完了したTask6"], in: app)
        XCTAssertTrue(app.staticTexts["完了したTask6"].isHittable)
        app.tabBars.buttons["Tasks"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["完了したTask6"].isHittable) // Returning without a resolution must not reset scrolling.
        scrollTo(app.staticTexts["12時に終了した予定"], in: app)
        XCTAssertFalse(app.staticTexts["敬老の日"].exists)
        screenshot(app, name: "Today — retained history")

        let unresolved = app.buttons["todayUnresolved"]
        for _ in 0..<8 where !unresolved.isHittable { app.swipeDown() }
        XCTAssertTrue(unresolved.isHittable)
        unresolved.tap()
        scrollTo(app.staticTexts["11時のTask"], in: app)
        app.staticTexts["11時のTask"].tap()
        app.buttons["実行を記録"].tap()
        app.buttons["記録"].tap()
        if !app.buttons["todayFocus"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        assertCentralFocus("17時のTask", in: app) // Resolving an expired slot also returns to the next action.

        app.tabBars.buttons["Tasks"].tap()
        scrollTo(app.staticTexts["完了したTask6"], in: app)
        app.tabBars.buttons["Insights"].tap()
        scrollTo(app.staticTexts["完了したTask6"], in: app)
        XCTAssertFalse(app.staticTexts["敬老の日"].exists)
    }

    @MainActor func testTodayNextWhenNothingIsCurrent() {
        let app = launch(largeText: true, todayFocus: true, noCurrent: true)
        assertCentralFocus("17時のTask", in: app)
        XCTAssertTrue(app.staticTexts["次"].exists)
        screenshot(app, name: "Today — next task at accessibility size")
    }

    @MainActor func testHomeSwipeSkipCancelRescheduleAndDelete() {
        let app = launch(todayFocus: true)
        let date = app.staticTexts["homeDate"].label
        let area = app.collectionViews.firstMatch
        area.swipeLeft()
        XCTAssertNotEqual(app.staticTexts["homeDate"].label, date)
        XCTAssertFalse(app.staticTexts["currentTaskTitle"].exists)
        area.swipeRight()
        XCTAssertEqual(app.staticTexts["homeDate"].label, date)
        XCTAssertTrue(app.buttons["skipCurrentTask"].waitForExistence(timeout: 5))
        app.buttons["skipCurrentTask"].tap()
        app.buttons["キャンセル"].tap()
        XCTAssertEqual(app.staticTexts["currentTaskTitle"].label, "16時のTask")
        app.buttons["skipCurrentTask"].tap()
        app.buttons["日時を変更"].tap()
        XCTAssertTrue(app.navigationBars["予定を変更"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["scheduleStart"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        XCTAssertFalse(app.staticTexts["currentTaskTitle"].exists)
        screenshot(app, name: "Home — rescheduled same Task")
        app.terminate()
        app.launch() // isolated in-memory fixture for archive flow
        XCTAssertTrue(app.buttons["skipCurrentTask"].waitForExistence(timeout: 5))
        app.buttons["skipCurrentTask"].tap()
        app.buttons["Taskを削除"].tap()
        XCTAssertTrue(app.alerts["Taskを削除しますか？"].waitForExistence(timeout: 5))
        app.alerts.buttons["キャンセル"].tap()
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.staticTexts["currentTaskTitle"].exists)
        app.buttons["skipCurrentTask"].tap()
        app.buttons["Taskを削除"].tap()
        app.alerts.buttons["削除する"].tap()
        XCTAssertFalse(app.staticTexts["currentTaskTitle"].exists)
        XCTAssertFalse(app.staticTexts["未スケジュール"].exists)
        screenshot(app, name: "Home — archived current Task")
    }

    @MainActor func testReusableCategoryAndTaskEditorSchedule() {
        let app = launch()
        app.tabBars.buttons["Tasks"].tap()
        app.buttons["globalAdd"].tap(); app.buttons["Task を追加"].tap()
        app.textFields["taskTitle"].tap(); app.textFields["taskTitle"].typeText("制作")
        app.buttons["categoryMenu"].tap(); app.buttons["新しいカテゴリを入力"].tap()
        app.textFields["newCategory"].tap(); app.textFields["newCategory"].typeText("アニメーション")
        app.buttons["saveTask"].tap()
        app.buttons["制作"].tap(); app.buttons["編集"].tap()
        XCTAssertTrue(app.switches["日時を設定"].exists)
        app.switches["日時を設定"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["scheduleStart"].firstMatch.waitForExistence(timeout: 5))
        screenshot(app, name: "Task editor — schedule and reusable category")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.staticTexts["未確定"].waitForExistence(timeout: 5))
        app.buttons["編集"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["scheduleStart"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["globalAdd"].tap(); app.buttons["Task を追加"].tap()
        app.buttons["categoryMenu"].tap()
        XCTAssertTrue(app.buttons["アニメーション"].waitForExistence(timeout: 5))
        app.buttons["アニメーション"].tap()
        app.textFields["taskTitle"].tap(); app.textFields["taskTitle"].typeText("次の制作")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.buttons["次の制作"].waitForExistence(timeout: 5))
    }

    @MainActor func testCurrentCardAtAccessibilitySize() {
        let app = launch(largeText: true, todayFocus: true)
        XCTAssertEqual(app.staticTexts["currentTaskTitle"].label, "16時のTask")
        scrollTo(app.buttons["completeCurrentTask"], in: app)
        XCTAssertTrue(app.buttons["skipCurrentTask"].isHittable)
        XCTAssertFalse(app.buttons["一時停止"].exists)
        screenshot(app, name: "Home — current Task at accessibility size")
    }

}
