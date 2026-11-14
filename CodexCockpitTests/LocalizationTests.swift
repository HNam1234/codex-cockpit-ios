import XCTest
@testable import CodexCockpit

final class LocalizationTests: XCTestCase {
    func testEnglishDeviceCodeAndNavigationCopyExists() {
        XCTAssertEqual(L10n.text("Nhập code từ PC", language: "en"), "Enter code from PC")
        XCTAssertEqual(L10n.text("Tiếp tục tự động", language: "en"), "Continue automatically")
        XCTAssertEqual(L10n.text("Tổng quan", language: "en"), "Overview")
        XCTAssertEqual(L10n.text("Cài đặt", language: "en"), "Settings")
    }

    func testEnglishDynamicQuotaAndSubscriptionCopyExists() {
        XCTAssertEqual(L10n.format("quota.reset.hours_minutes", 2, 18, language: "en"), "Resets in 2 hours 18 minutes")
        XCTAssertEqual(L10n.format("subscription.days", 3, language: "en"), "3 days remaining")
        XCTAssertEqual(L10n.text("health.needs_login", language: "en"), "Sign in required")
        XCTAssertEqual(L10n.text("tibo.status.confirmed", language: "en"), "CONFIRMED")
    }

    func testVietnameseRemainsAvailable() {
        XCTAssertEqual(L10n.text("Nhập code từ PC", language: "vi"), "Nhập code từ PC")
        XCTAssertEqual(L10n.format("subscription.days", 3, language: "vi"), "Còn 3 ngày")
    }

    func testCockpitOAuthRelayCopyExistsInBothLanguages() {
        XCTAssertEqual(L10n.text("oauth.relay.entry.title", language: "en"), "Cockpit OAuth")
        XCTAssertEqual(L10n.text("oauth.relay.entry.title", language: "vi"), "OAuth Cockpit")
        XCTAssertEqual(L10n.text("oauth.relay.entry.open", language: "en"), "Open in this WebKit")
        XCTAssertEqual(L10n.text("oauth.relay.entry.open", language: "vi"), "Mở trong WebKit này")
        XCTAssertEqual(L10n.text("oauth.relay.result.title", language: "en"), "Authorization captured")
        XCTAssertEqual(L10n.text("oauth.relay.result.title", language: "vi"), "Đã nhận ủy quyền")
        XCTAssertEqual(L10n.text("oauth.relay.result.copy", language: "en"), "Copy callback")
        XCTAssertEqual(L10n.text("oauth.relay.result.copy", language: "vi"), "Copy callback")
    }

    func testCockpitOAuthRelayErrorsAreLocalizedWithoutSecretValues() {
        for error in [
            CockpitOAuthRelayError.invalidAuthorizationURL,
            .unsupportedAuthorizationURL,
            .invalidHostedAuthorizationURL,
            .invalidAuthorizationParameters,
            .invalidRedirectURI,
            .invalidCallback,
            .callbackMismatch,
            .stateMismatch
        ] {
            let english = L10n.text(error.localizationKey, language: "en")
            let vietnamese = L10n.text(error.localizationKey, language: "vi")
            XCTAssertNotEqual(english, error.localizationKey)
            XCTAssertNotEqual(vietnamese, error.localizationKey)
            XCTAssertFalse(english.contains("state-123"))
            XCTAssertFalse(vietnamese.contains("state-123"))
        }
    }
}
