//
//  ReelFlowUITests.swift
//  ReelFlowUITests
//
//  Created by 牧云踏歌 on 2026/2/6.
//

import XCTest

final class ReelFlowUITests: XCTestCase {
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

        XCTAssertTrue(app.buttons["failure_primary_action"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["failure_open_log"].waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.staticTexts["workflow_status_message"].exists)
    }

    @MainActor
    func testSuccessScenarioShowsSuccessSheet() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "success"]
        app.launch()

        XCTAssertTrue(elementByIdentifier(app, id: "success_sheet").waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["打开文件夹"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["查看日志"].waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.staticTexts["workflow_status_message"].exists)
    }

    @MainActor
    func testFailureRecoveryActionCanReachSuccessSheet() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "failure_then_success"]
        app.launch()

        let retryButton = app.buttons["failure_primary_action"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: uiTimeout))
        retryButton.tap()

        XCTAssertTrue(elementByIdentifier(app, id: "success_sheet").waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["打开文件夹"].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["查看日志"].waitForExistence(timeout: uiTimeout))
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
        XCTAssertTrue(waitEnabled(export))
        XCTAssertFalse(app.staticTexts["workflow_status_message"].exists)
    }

    @MainActor
    func testPreflightLocateSwitchesBackToAllAssetsAndFocusesTarget() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "preflight_navigation"]
        app.launch()

        let locateFirstIssue = elementByIdentifier(app, id: "preflight_locate_first_issue")
        XCTAssertTrue(locateFirstIssue.waitForExistence(timeout: uiTimeout))
        locateFirstIssue.tap()

        let plainAsset = elementByIdentifier(app, id: "asset_card_plain_sample_jpg")
        let reviewAsset = elementByIdentifier(app, id: "asset_card_review_sample_jpg")
        let reviewIssue = elementByIdentifier(app, id: "preflight_issue_review_sample_jpg")

        XCTAssertTrue(plainAsset.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(reviewAsset.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(["selected", "focused"].contains(reviewAsset.value as? String))
        XCTAssertEqual(reviewIssue.value as? String, "selected")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
