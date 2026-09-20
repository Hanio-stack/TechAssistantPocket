//
//  TechAssistantPocketUITestsLaunchTests.swift
//  TechAssistantPocketUITests
//
//  Created by 腐った卵 on 2026/09/19.
//

import XCTest

final class TechAssistantPocketUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Normal persistent app startup, using the real platform services without requesting access.
        XCTAssertTrue(app.buttons["はじめる"].waitForExistence(timeout: 10) || app.tabBars.buttons["Today"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
