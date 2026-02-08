//
//  PhotoTimeUITests.swift
//  PhotoTimeUITests
//
//  Created by 牧云踏歌 on 2026/2/6.
//

import XCTest

final class PhotoTimeUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testPrimarySecondaryActionGroupsAndInitialButtonState() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["group_primary_actions"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["group_secondary_actions"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["primary_export"].isEnabled)
        XCTAssertFalse(app.buttons["primary_cancel"].isEnabled)
        XCTAssertFalse(app.buttons["secondary_retry_export"].isEnabled)
    }

    @MainActor
    func testFailureScenarioShowsFailureCard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "failure"]
        app.launch()

        XCTAssertTrue(app.otherElements["failure_card"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["failure_primary_action"].isEnabled)
        XCTAssertTrue(app.buttons["failure_open_log"].isEnabled)
    }

    @MainActor
    func testSuccessScenarioShowsSuccessCard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "success"]
        app.launch()

        XCTAssertTrue(app.otherElements["success_card"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["success_open_output"].isEnabled)
        XCTAssertTrue(app.buttons["success_export_again"].isEnabled)
    }

    @MainActor
    func testInvalidScenarioShowsInlineValidation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "invalid"]
        app.launch()

        XCTAssertTrue(app.staticTexts["settings_validation_message"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
