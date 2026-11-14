import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchesDirectlyIntoMainTabsWithoutLockScreen() {
        let app = localizedApp(language: "vi", locale: "vi_VN", mode: "static")
        app.launch()

        XCTAssertTrue(app.staticTexts["cockpit-ready"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Tổng quan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["WebKit"].exists)
        XCTAssertTrue(app.tabBars.buttons["Cài đặt"].exists)
        XCTAssertFalse(app.buttons["Mở bằng Face ID / mật mã"].exists)
    }

    func testMainShellStaysInForeground() {
        let app = localizedApp(language: "vi", locale: "vi_VN", mode: "webview")
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Tổng quan"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.state, .runningForeground)
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testEnglishLocalizationShowsEnglishTabs() {
        let app = localizedApp(language: "en", locale: "en_US", mode: "static")
        app.launch()

        XCTAssertTrue(app.staticTexts["cockpit-ready"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Overview"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["WebKit"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    private func localizedApp(language: String, locale: String, mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchEnvironment["UITEST_MODE"] = mode
        return app
    }
}
