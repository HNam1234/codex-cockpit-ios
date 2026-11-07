import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesDirectlyIntoMainTabsWithoutLockScreen() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Cockpit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["5 tài khoản"].exists)
        XCTAssertTrue(app.tabBars.buttons["Cài đặt"].exists)
        XCTAssertFalse(app.buttons["Mở bằng Face ID / mật mã"].exists)
    }
}
