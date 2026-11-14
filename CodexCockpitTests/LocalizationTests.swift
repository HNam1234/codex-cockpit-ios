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
}
