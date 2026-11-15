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
        XCTAssertTrue(app.tabBars.buttons["Thư"].exists)
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
        XCTAssertTrue(app.tabBars.buttons["Mail"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testMailEmptyStateAndCreateSheetDefaultToSixtyDays() {
        let app = localizedApp(language: "en", locale: "en_US", mode: "static")
        app.launchEnvironment["PREVIEW_TAB"] = "mail"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["mail-empty"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["mail-attribution"].exists)
        let create = app.buttons["mail-create"]
        XCTAssertTrue(create.exists)
        create.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mail-create-sheet"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["mail-lifetime-60"].value as? String, "selected")
    }

    func testMailSampleShowsMappingInboxSafeMessageCodesAndAttachmentMetadata() {
        let app = localizedApp(language: "en", locale: "en_US", mode: "static")
        app.launchEnvironment["PREVIEW_TAB"] = "mail"
        app.launchEnvironment["PREVIEW_MAIL_SAMPLE"] = "1"
        app.launch()

        let card = app.buttons["mail-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["preview@example.test"].exists)
        XCTAssertTrue(app.staticTexts["preview.account@example.com · WebKit 1"].exists)
        XCTAssertTrue(app.staticTexts["1 unread"].exists)
        card.tap()

        XCTAssertTrue(app.descendants(matching: .any)["mail-inbox"].waitForExistence(timeout: 5))
        let message = app.buttons["mail-message-row"]
        XCTAssertTrue(message.exists)
        XCTAssertTrue(app.staticTexts["Verify your account"].exists)
        message.tap()

        XCTAssertTrue(app.descendants(matching: .any)["mail-message-detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mail-code-482731"].exists)
        XCTAssertTrue(app.buttons["mail-code-A9K2"].exists)
        XCTAssertTrue(app.staticTexts["Your verification code is 482731. Backup code A9K2."].exists)
        XCTAssertTrue(app.staticTexts["notice.txt"].exists)
    }

    func testCockpitOAuthEntryValidatesBeforeOpeningWebKit() {
        let app = localizedApp(language: "en", locale: "en_US", mode: "static")
        app.launchEnvironment["PREVIEW_TAB"] = "profiles"
        app.launchEnvironment["PREVIEW_COCKPIT_OAUTH_ENTRY"] = "1"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["cockpit-oauth-entry"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["cockpit-oauth-identity"].exists)
        let field = app.textFields["cockpit-oauth-url-field"]
        let open = app.buttons["cockpit-oauth-open"]
        XCTAssertTrue(field.exists)
        XCTAssertTrue(open.exists)
        XCTAssertFalse(open.isEnabled)

        field.tap()
        field.typeText("https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_test&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&state=state-123&code_challenge=challenge-123&code_challenge_method=S256")
        XCTAssertTrue(open.isEnabled)
    }

    func testCockpitOAuthResultOffersCopyAndClearControls() {
        let app = localizedApp(language: "vi", locale: "vi_VN", mode: "static")
        app.launchEnvironment["PREVIEW_TAB"] = "profiles"
        app.launchEnvironment["PREVIEW_COCKPIT_OAUTH_RESULT"] = "1"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["cockpit-oauth-result"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["cockpit-oauth-copy"].exists)
        XCTAssertTrue(app.buttons["cockpit-oauth-clear"].exists)
    }

    private func localizedApp(language: String, locale: String, mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchEnvironment["UITEST_MODE"] = mode
        return app
    }
}
