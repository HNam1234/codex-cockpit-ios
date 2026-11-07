import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesDirectlyIntoMainTabsWithoutLockScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "static"
        app.launch()

        XCTAssertTrue(app.staticTexts["cockpit-ready"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Tổng quan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["WebKit"].exists)
        XCTAssertTrue(app.tabBars.buttons["Cài đặt"].exists)
        XCTAssertFalse(app.buttons["Mở bằng Face ID / mật mã"].exists)
    }

    func testMainShellStaysInForeground() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "webview"
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Tổng quan"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.state, .runningForeground)
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
