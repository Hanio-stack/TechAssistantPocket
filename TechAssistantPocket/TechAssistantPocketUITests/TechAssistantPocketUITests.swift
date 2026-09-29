import XCTest

final class TechAssistantPocketUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(seed: Bool = false, largeText: Bool = false, denied: Bool = false,
                                   todayFocus: Bool = false, noCurrent: Bool = false, durationEdit: Bool = false, sixFixes: Bool = false, lifeDay: Bool = false, lifeSetup: Bool = false) -> XCUIApplication {
        // Launch smoke tests also exercise landscape; each interaction test starts in portrait.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if sixFixes { app.launchArguments.append("--ui-six-fixes") }
        if lifeDay { app.launchArguments.append("--ui-life-day") }
        if lifeSetup { app.launchArguments.append("--ui-life-setup") }
        if denied { app.launchArguments.append("--ui-denied") }
        if seed { app.launchArguments.append("--ui-seed") }
        if todayFocus { app.launchArguments.append("--ui-today-focus") }
        if noCurrent { app.launchArguments.append("--ui-no-current") }
        if durationEdit { app.launchArguments.append("--ui-edit-duration") }
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
        XCTAssertTrue(app.buttons["taskLink-読書"].waitForExistence(timeout: 5))
        app.buttons["taskLink-読書"].tap()
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
        XCTAssertFalse(app.buttons["実行を記録"].exists)
        XCTAssertFalse(app.buttons["できなかった"].exists)
        app.buttons["キャンセル"].tap()
        app.buttons["予定をキャンセル"].tap()
        XCTAssertTrue(app.staticTexts["キャンセル"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Task を削除"].tap()
        app.buttons["削除する"].tap()
        XCTAssertTrue(app.staticTexts["やりたいことを追加"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["未分類"].waitForExistence(timeout: 5))
        screenshot(app, name: "Archived history in Insights")
    }

    @MainActor func testTodayReviewInsightsAndOrdinaryEvent() {
        let app = launch(seed: true)
        app.buttons["homeRecords"].tap()
        scrollTo(app.staticTexts["友達と昼食"], in: app)
        screenshot(app, name: "Today — Tasks and ordinary Event")
        scrollTo(app.buttons["reviewCTA"], in: app)
        app.buttons["reviewCTA"].tap()
        XCTAssertTrue(app.navigationBars["一日を振り返る"].waitForExistence(timeout: 5))
        screenshot(app, name: "Review — Japanese")
        scrollTo(app.buttons["できなかった"], in: app)
        app.buttons["できなかった"].tap()
        let finishReview = app.buttons["finishReview"]
        for _ in 0..<4 where !finishReview.isHittable { app.swipeUp() }
        XCTAssertTrue(finishReview.isHittable)
        XCTAssertTrue(finishReview.isEnabled)
        finishReview.tap()
        app.buttons["閉じる"].tap()
        app.tabBars.buttons["Insights"].tap()
        screenshot(app, name: "Insights — weekly success rate")
        let taskInsight = app.staticTexts["未分類"]
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
        app.buttons["homeRecords"].tap()
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
        XCTAssertTrue(app.buttons["taskLink-連携なしTask"].waitForExistence(timeout: 5))
        app.buttons["globalAdd"].tap()
        app.buttons["予定を追加"].tap()
        scrollTo(app.staticTexts["calendarDeniedHelp"], in: app)
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
        XCTAssertEqual(app.staticTexts["currentTaskTitle"].label, "16時のTask")
        XCTAssertTrue(app.buttons["skipCurrentTask"].isHittable)
        XCTAssertTrue(app.buttons["completeCurrentTask"].isHittable)
        XCTAssertFalse(app.buttons["一時停止"].exists)
        XCTAssertFalse(app.staticTexts["完了したTask6"].exists)
        screenshot(app, name: "Deck — current with stacked upcoming cards")
        app.buttons["completeCurrentTask"].tap()
        app.buttons["記録"].tap()
        assertCentralFocus("17時のTask", in: app)
        screenshot(app, name: "Deck — next card after completion")
        app.buttons["homeRecords"].tap()
        scrollTo(app.staticTexts["自分の終日予定"], in: app)
        XCTAssertFalse(app.staticTexts["敬老の日"].exists)
        scrollTo(app.staticTexts["完了したTask6"], in: app)
        screenshot(app, name: "Deck — history preserved outside main screen")
        scrollTo(app.staticTexts["12時に終了した予定"], in: app)
        app.buttons["閉じる"].tap()
        app.buttons["homeRecords"].tap()
        scrollTo(app.staticTexts["11時のTask"], in: app)
        app.staticTexts["11時のTask"].tap()
        app.buttons["実行を記録"].tap()
        app.buttons["記録"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["閉じる"].tap()
        assertCentralFocus("17時のTask", in: app)
        app.tabBars.buttons["Insights"].tap()
        scrollTo(app.staticTexts["未分類"], in: app)
        app.staticTexts["未分類"].tap()
        XCTAssertTrue(app.staticTexts["実行件数 6件"].waitForExistence(timeout: 5))
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
        let area = app.scrollViews.firstMatch
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
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "18時")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["currentTaskTitle"].waitForNonExistence(timeout: 5))
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
        app.buttons["taskLink-制作"].tap(); app.buttons["編集"].tap()
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
        XCTAssertTrue(app.buttons["taskLink-次の制作"].waitForExistence(timeout: 5))
    }

    @MainActor func testTitleOnlyEditPreservesTaskEstimateAndStartedPlan() {
        let app = launch(durationEdit: true)
        app.tabBars.buttons["Tasks"].tap()
        app.buttons.matching(NSPredicate(format: "identifier == %@", "taskLink-所要時間保持の確認")).firstMatch.tap()
        app.buttons["編集"].tap()
        app.textFields["taskTitle"].tap()
        app.textFields["taskTitle"].typeText("・編集済み")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.navigationBars["所要時間保持の確認・編集済み"].waitForExistence(timeout: 5))
        // Removing the unstarted plan exposes the Task's independent estimate.
        app.buttons["編集"].tap()
        app.switches["日時を設定"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.staticTexts["まだ記録がありません"].waitForExistence(timeout: 5))
        app.buttons["編集"].tap()
        XCTAssertTrue(app.steppers["所要時間 10分"].waitForExistence(timeout: 5))
        screenshot(app, name: "Task editor — original estimate retained")
        app.buttons["キャンセル"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "identifier == %@", "taskLink-開始済み所要時間保持")).firstMatch.tap()
        app.buttons["編集"].tap()
        app.textFields["taskTitle"].tap()
        app.textFields["taskTitle"].typeText("・編集済み")
        app.buttons["saveTask"].tap()
        XCTAssertTrue(app.navigationBars["開始済み所要時間保持・編集済み"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["未確定"].exists)
        app.tabBars.buttons["Today"].tap()
        XCTAssertEqual(app.staticTexts["currentTaskTitle"].label, "開始済み所要時間保持・編集済み")
        XCTAssertTrue(app.buttons["expandDeck"].label.contains("1件"))
        XCTAssertFalse(app.staticTexts["未スケジュール"].exists)
        screenshot(app, name: "Home — current Task without a next plan")
    }

    @MainActor func testCurrentCardAtAccessibilitySize() {
        let app = launch(largeText: true, todayFocus: true)
        XCTAssertEqual(app.staticTexts["currentTaskTitle"].label, "16時のTask")
        scrollTo(app.buttons["completeCurrentTask"], in: app)
        XCTAssertTrue(app.buttons["skipCurrentTask"].isHittable)
        XCTAssertFalse(app.buttons["一時停止"].exists)
        screenshot(app, name: "Home — current Task at accessibility size")
    }

    @MainActor func testSavedTimeAndMinuteSelectionImmediatelySave() {
        let app = launch(sixFixes: true)
        app.tabBars.buttons["Tasks"].tap()
        app.buttons["taskLink-21時の制作"].tap()
        app.buttons["編集"].tap()
        XCTAssertTrue((app.pickerWheels.element(boundBy: 0).value as? String ?? "").contains("21"))
        XCTAssertTrue((app.pickerWheels.element(boundBy: 1).value as? String ?? "").contains("15"))
        XCTAssertTrue(app.buttons["reminderPicker"].label.contains("15分前"))
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "22時")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "30分")
        app.buttons["saveTask"].tap() // No focus change or extra dismissal between selecting and saving.
        XCTAssertTrue(app.navigationBars["21時の制作"].waitForExistence(timeout: 5))
        app.buttons["編集"].tap()
        XCTAssertTrue((app.pickerWheels.element(boundBy: 0).value as? String ?? "").contains("22"))
        XCTAssertTrue((app.pickerWheels.element(boundBy: 1).value as? String ?? "").contains("30"))
        XCTAssertTrue(app.buttons["reminderPicker"].label.contains("15分前"))
        screenshot(app, name: "Saved 22:30 and original reminder")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "45分")
        app.buttons["saveTask"].tap()
        app.buttons["編集"].tap()
        XCTAssertTrue((app.pickerWheels.element(boundBy: 1).value as? String ?? "").contains("45"))
        app.buttons["キャンセル"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["taskLink-開始済みの制作"].tap()
        app.staticTexts["未確定"].tap()
        app.buttons["予定を変更"].tap()
        XCTAssertTrue((app.pickerWheels.element(boundBy: 0).value as? String ?? "").contains("19"))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["未確定"].waitForExistence(timeout: 5))
        app.buttons["予定を変更"].tap()
        XCTAssertTrue((app.pickerWheels.element(boundBy: 0).value as? String ?? "").contains("19"))
    }

    @MainActor func testNewTaskReminderDefaultsToStart() {
        let app = launch()
        app.buttons["globalAdd"].tap(); app.buttons["Task を追加"].tap()
        app.textFields["taskTitle"].tap(); app.textFields["taskTitle"].typeText("通知確認")
        app.switches["日時を設定"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["reminderPicker"].label.contains("開始時刻"))
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "22時")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "30分")
        app.buttons["saveTask"].tap()
        app.tabBars.buttons["Tasks"].tap()
        app.buttons["taskLink-通知確認"].tap(); app.buttons["編集"].tap()
        XCTAssertTrue(app.buttons["reminderPicker"].label.contains("開始時刻"))
        XCTAssertTrue((app.pickerWheels.element(boundBy: 0).value as? String ?? "").contains("22"))
        XCTAssertTrue((app.pickerWheels.element(boundBy: 1).value as? String ?? "").contains("30"))
    }

    @MainActor func testLifeDayHomeCategoryAndSettingsRefresh() {
        let app = launch(lifeDay: true)
        XCTAssertEqual(app.staticTexts["currentTaskCategory"].label, "BK進捗")
        XCTAssertEqual(app.staticTexts["currentTaskTitle"].label, "深夜の制作")
        scrollTo(app.staticTexts["homeDate"], in: app)
        XCTAssertTrue(app.staticTexts["homeDate"].label.contains("24"))
        screenshot(app, name: "Life day September 24 at 00:45")
        app.scrollViews.firstMatch.swipeLeft()
        XCTAssertTrue(app.staticTexts["homeDate"].label.contains("25"))
        app.scrollViews.firstMatch.swipeRight()
        XCTAssertTrue(app.staticTexts["homeDate"].label.contains("24"))
        app.buttons["設定"].tap(); app.buttons["起床・就寝を変更"].tap()
        app.pickerWheels.element(boundBy: 2).adjust(toPickerWheelValue: "0時")
        app.buttons["saveLifeHours"].tap(); app.buttons["完了"].tap()
        XCTAssertFalse(app.staticTexts["currentTaskTitle"].exists)
        scrollTo(app.staticTexts["homeDate"], in: app)
        XCTAssertTrue(app.staticTexts["homeDate"].label.contains("25"))
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(app.buttons["taskLink-深夜の制作"].label.contains("BK進捗"))
        screenshot(app, name: "Category above individual Task")
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.staticTexts["カテゴリ別"].exists)
        app.staticTexts["BK進捗"].tap()
        XCTAssertTrue(app.navigationBars["BK進捗"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "データ不足")).firstMatch.exists)
        screenshot(app, name: "Category Insights with insufficient evidence")
    }

    @MainActor func testLifeSetupOnlyUntilSaved() {
        let app = launch(lifeSetup: true)
        XCTAssertTrue(app.navigationBars["生活時間を設定"].waitForExistence(timeout: 5))
        app.buttons["saveLifeHours"].tap()
        XCTAssertFalse(app.navigationBars["生活時間を設定"].exists)
        app.terminate()
        app.launchArguments.append("--ui-preserve-defaults")
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Tasks"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["生活時間を設定"].exists)
    }

    @MainActor func testDeckInteractiveDragExpansionAndFutureCancel() {
        let app = launch(todayFocus: true)
        let originalDay = app.staticTexts["homeDate"].label
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.46))
        let short = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.46))
        start.press(forDuration: 0.05, thenDragTo: short, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertEqual(app.staticTexts["homeDate"].label, originalDay)
        screenshot(app, name: "Deck — short drag returned")
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.46))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertNotEqual(app.staticTexts["homeDate"].label, originalDay)
        screenshot(app, name: "Deck — next life day")
        app.buttons["previousDay"].tap()
        XCTAssertEqual(app.staticTexts["homeDate"].label, originalDay)
        app.buttons["expandDeck"].tap()
        screenshot(app, name: "Deck — expanded cards")
        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "deckDetails-")).firstMatch
        scrollTo(next, in: app); next.tap()
        XCTAssertTrue(app.buttons["予定を変更"].exists)
        XCTAssertFalse(app.buttons["実行を記録"].exists)
        XCTAssertFalse(app.buttons["できなかった"].exists)
        XCTAssertFalse(app.buttons["キャンセルした"].exists)
        app.buttons["キャンセル"].tap()
        app.buttons["予定をキャンセル"].tap()
        if app.navigationBars["Today"].exists {
            app.buttons["homeRecords"].tap()
        }
        scrollTo(app.staticTexts["キャンセル"].firstMatch, in: app)
        screenshot(app, name: "Future cancellation retained in history")
    }

}
