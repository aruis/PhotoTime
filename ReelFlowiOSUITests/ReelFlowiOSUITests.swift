import XCTest

final class ReelFlowiOSUITests: XCTestCase {
    func testEmptyStateShowsImportPrompt() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["ios_pick_photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ios_selected_count"].label.contains("尚未选择"))
    }

    func testReadyScenarioCanExportAndRevealShareActions() {
        let app = XCUIApplication()
        app.launchArguments += ["-ios-ui-test-scenario", "ready"]
        app.launch()

        XCTAssertTrue(app.otherElements["ios_preview_surface"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["ios_shutter_toggle"].exists)

        app.buttons["ios_export_button"].tap()

        XCTAssertTrue(app.buttons["ios_share_video"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["ios_save_video"].exists)
    }
}
