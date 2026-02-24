//
//  PhotoTimeUITests.swift
//  PhotoTimeUITests
//
//  Created by 牧云踏歌 on 2026/2/6.
//

import XCTest

final class PhotoTimeUITests: XCTestCase {
    private let uiTimeout: TimeInterval = 3

    private func button(_ app: XCUIApplication, id: String, title: String, timeout: TimeInterval? = nil) -> XCUIElement {
        let wait = timeout ?? uiTimeout
        let byID = app.buttons.matching(identifier: id).firstMatch
        if byID.waitForExistence(timeout: wait) {
            return byID
        }
        let byTitle = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        _ = byTitle.waitForExistence(timeout: wait)
        return byTitle
    }

    private func waitEnabled(_ element: XCUIElement, timeout: TimeInterval = 2) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func elementByIdentifier(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

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

        let selectImages = elementByIdentifier(app, id: "primary_select_images")
        let export = elementByIdentifier(app, id: "primary_export")
        let cancel = elementByIdentifier(app, id: "primary_cancel")
        let moreMenu = elementByIdentifier(app, id: "toolbar_more_menu")

        XCTAssertFalse(selectImages.exists)
        XCTAssertFalse(export.exists)
        XCTAssertFalse(cancel.exists)
        XCTAssertTrue(moreMenu.waitForExistence(timeout: uiTimeout))

        moreMenu.tap()
        let selectOutput = elementByIdentifier(app, id: "primary_select_output")
        XCTAssertTrue(selectOutput.waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.staticTexts["flow_next_hint"].exists)
    }

    @MainActor
    func testFailureScenarioShowsFailureCard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "failure"]
        app.launch()

        XCTAssertTrue(app.staticTexts["workflow_status_message"].waitForExistence(timeout: uiTimeout))
        let status = app.staticTexts["workflow_status_message"].label
        XCTAssertFalse(status.contains("请选择图片并设置导出路径"), "status=\(status)")
        XCTAssertTrue(app.buttons["failure_primary_action"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["failure_open_log"].waitForExistence(timeout: uiTimeout))
    }

    @MainActor
    func testSuccessScenarioShowsSuccessCard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "success"]
        app.launch()

        XCTAssertTrue(app.staticTexts["workflow_status_message"].waitForExistence(timeout: uiTimeout))
        let status = app.staticTexts["workflow_status_message"].label
        XCTAssertFalse(status.contains("请选择图片并设置导出路径"), "status=\(status)")
        XCTAssertTrue(app.buttons["success_open_output"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["success_open_log"].waitForExistence(timeout: uiTimeout))
    }

    @MainActor
    func testFailureRecoveryActionCanReachSuccessCard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "failure_then_success"]
        app.launch()

        let retryButton = app.buttons["failure_primary_action"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: uiTimeout))
        retryButton.tap()

        XCTAssertTrue(app.buttons["success_open_output"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["success_open_log"].waitForExistence(timeout: uiTimeout))
    }

    @MainActor
    func testInvalidScenarioShowsInlineValidation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "invalid"]
        app.launch()

        XCTAssertTrue(app.staticTexts["settings_validation_message"].waitForExistence(timeout: uiTimeout))
    }

    @MainActor
    func testFirstRunReadyScenarioAllowsExport() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "first_run_ready"]
        app.launch()

        let export = button(app, id: "primary_export", title: "导出 MP4")

        XCTAssertTrue(export.exists)
        XCTAssertTrue(app.staticTexts["workflow_status_message"].waitForExistence(timeout: uiTimeout))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
