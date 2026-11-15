import XCTest
@testable import CodexCockpit

final class LocalizationTests: XCTestCase {
    func testEnglishDeviceCodeAndNavigationCopyExists() {
        XCTAssertEqual(L10n.text("Nhập code từ PC", language: "en"), "Enter code from PC")
        XCTAssertEqual(L10n.text("Tiếp tục tự động", language: "en"), "Continue automatically")
        XCTAssertEqual(L10n.text("Tổng quan", language: "en"), "Overview")
        XCTAssertEqual(L10n.text("Cài đặt", language: "en"), "Settings")
        XCTAssertEqual(L10n.text("mail.tab", language: "en"), "Mail")
        XCTAssertEqual(L10n.text("mail.tab", language: "vi"), "Thư")
    }

    func testDisposableMailCopyExistsInBothLanguages() {
        XCTAssertEqual(L10n.text("mail.empty.title", language: "en"), "No temporary mailboxes")
        XCTAssertEqual(L10n.text("mail.empty.title", language: "vi"), "Chưa có hộp thư tạm")
        XCTAssertEqual(L10n.text("mail.create.title", language: "en"), "New temporary mailbox")
        XCTAssertEqual(L10n.text("mail.create.title", language: "vi"), "Tạo hộp thư tạm")
        XCTAssertEqual(L10n.text("mail.lifetime.60", language: "en"), "60 days")
        XCTAssertEqual(L10n.text("mail.lifetime.60", language: "vi"), "60 ngày")
        XCTAssertEqual(L10n.text("mail.code.copy", language: "en"), "Copy code")
        XCTAssertEqual(L10n.text("mail.code.copy", language: "vi"), "Copy mã")
        XCTAssertEqual(L10n.text("mail.provider.attribution", language: "en"), "Mail service by Mail.tm")
        XCTAssertEqual(L10n.text("mail.provider.attribution", language: "vi"), "Dịch vụ thư bởi Mail.tm")
    }

    func testEnglishDynamicQuotaAndSubscriptionCopyExists() {
        XCTAssertEqual(L10n.format("quota.reset.hours_minutes", 2, 18, language: "en"), "Resets in 2 hours 18 minutes")
        XCTAssertEqual(L10n.format("subscription.days", 3, language: "en"), "3 days remaining")
        XCTAssertEqual(L10n.text("health.needs_login", language: "en"), "Sign in required")
        XCTAssertEqual(L10n.text("tibo.status.confirmed", language: "en"), "CONFIRMED")
        XCTAssertEqual(L10n.text("oauth.direct.connected.compact", language: "en"), "Connected")
        XCTAssertEqual(L10n.text("quota.manage_usage", language: "en"), "View official Usage")
    }

    func testVietnameseRemainsAvailable() {
        XCTAssertEqual(L10n.text("Nhập code từ PC", language: "vi"), "Nhập code từ PC")
        XCTAssertEqual(L10n.format("subscription.days", 3, language: "vi"), "Còn 3 ngày")
        XCTAssertEqual(L10n.text("oauth.direct.connected.compact", language: "vi"), "Đã kết nối")
        XCTAssertEqual(L10n.text("quota.manage_usage", language: "vi"), "Xem Usage chính thức")
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
