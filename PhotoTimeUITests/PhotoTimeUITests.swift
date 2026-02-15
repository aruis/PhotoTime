//
//  PhotoTimeUITests.swift
//  PhotoTimeUITests
//
//  Created by 牧云踏歌 on 2026/2/6.
//

import XCTest

final class PhotoTimeUITests: XCTestCase {
    private func button(_ app: XCUIApplication, id: String, title: String, timeout: TimeInterval = 2) -> XCUIElement {
        let byID = app.buttons.matching(identifier: id).firstMatch
        if byID.waitForExistence(timeout: timeout) {
            return byID
        }
        let byTitle = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        _ = byTitle.waitForExistence(timeout: timeout)
        return byTitle
    }

    private func waitEnabled(_ element: XCUIElement, timeout: TimeInterval = 2) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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

        let selectImages = button(app, id: "primary_select_images", title: "选择图片")
        let selectOutput = button(app, id: "primary_select_output", title: "选择导出路径")
        let export = button(app, id: "primary_export", title: "导出 MP4")
        let cancel = button(app, id: "primary_cancel", title: "取消导出")

        XCTAssertTrue(selectImages.exists)
        XCTAssertTrue(selectOutput.exists)
        XCTAssertTrue(export.exists)
        XCTAssertTrue(cancel.exists)
        XCTAssertTrue(app.staticTexts["flow_next_hint"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testFailureScenarioShowsFailureCard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "failure"]
        app.launch()

        XCTAssertTrue(app.staticTexts["workflow_status_message"].waitForExistence(timeout: 2))
        let status = app.staticTexts["workflow_status_message"].label
        XCTAssertFalse(status.contains("请选择图片并设置导出路径"), "status=\(status)")
        XCTAssertTrue(app.buttons["failure_primary_action"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["failure_open_log"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSuccessScenarioShowsSuccessCard() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "success"]
        app.launch()

        XCTAssertTrue(app.staticTexts["workflow_status_message"].waitForExistence(timeout: 2))
        let status = app.staticTexts["workflow_status_message"].label
        XCTAssertFalse(status.contains("请选择图片并设置导出路径"), "status=\(status)")
        XCTAssertTrue(app.buttons["success_open_output"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["success_open_log"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testInvalidScenarioShowsInlineValidation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "invalid"]
        app.launch()

        XCTAssertTrue(app.staticTexts["settings_validation_message"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testFirstRunReadyScenarioAllowsExport() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-scenario", "first_run_ready"]
        app.launch()

        let export = button(app, id: "primary_export", title: "导出 MP4")

        XCTAssertTrue(export.exists)
        XCTAssertTrue(app.staticTexts["workflow_status_message"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
