import Foundation
import XCTest
@testable import CodexCockpit

final class SubscriptionStatusTests: XCTestCase {
    func testDecodesSubscriptionExpirationFromNativeAPI() throws {
        let data = Data(
            """
            {
              "id": "2",
              "name": "Codex 2",
              "display_name": null,
              "email": null,
              "plan": "plus",
              "subscription_expires_at": 2000000000,
              "ok": true,
              "error": null,
              "windows": [],
              "reset_credits": 0,
              "checked_at": 100
            }
            """.utf8
        )

        let account = try JSONDecoder().decode(AccountSnapshot.self, from: data)

        XCTAssertEqual(account.subscriptionExpiresAt, 2_000_000_000)
        XCTAssertEqual(account.subscriptionExpirationDate?.timeIntervalSince1970, 2_000_000_000)
    }

    func testRemainingSubscriptionUsesCeilingAndFallsBackToHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            account(expiresAt: 1_000_000 + Int(2.1 * 86_400)).subscriptionRemainingText(at: now),
            L10n.format("subscription.days", 3)
        )
        XCTAssertEqual(
            account(expiresAt: 1_000_000 + Int(23.1 * 3_600)).subscriptionRemainingText(at: now),
            L10n.format("subscription.hours", 24)
        )
        XCTAssertEqual(
            account(expiresAt: 1_000_000 + 1_800).subscriptionRemainingText(at: now),
            L10n.text("subscription.less_hour")
        )
    }

    func testExpiredSubscriptionIsExplicit() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let account = account(expiresAt: 999_999)

        XCTAssertEqual(account.subscriptionRemainingText(at: now), L10n.text("subscription.expired"))
        XCTAssertTrue(account.subscriptionIsExpired(at: now))
    }

    func testQuotaResetCountdownUsesReadableAndCompactFormats() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let window = quotaWindow(remaining: 80, resetsAt: 1_000_000 + 2 * 3_600 + 18 * 60)

        XCTAssertEqual(window.resetCountdownText(at: now), L10n.format("quota.reset.hours_minutes", 2, 18))
        XCTAssertEqual(window.resetCountdownText(at: now, compact: true), "2g 18p")
        XCTAssertEqual(quotaWindow(remaining: 80, resetsAt: 999_999).resetCountdownText(at: now), "Đang cập nhật kỳ mới")
    }

    func testAccountHealthPrioritizesLoginExpirationAndQuota() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(account(expiresAt: 2_000_000, ok: false).health(at: now), .needsLogin)
        XCTAssertEqual(account(expiresAt: 999_999).health(at: now), .expired)
        XCTAssertEqual(account(expiresAt: 1_000_000 + 2 * 86_400).health(at: now), .expiring)
        XCTAssertEqual(account(expiresAt: 2_000_000, remaining: 8).health(at: now), .quotaCritical)
        XCTAssertEqual(account(expiresAt: 2_000_000, remaining: 18).health(at: now), .quotaLow)
        XCTAssertEqual(account(expiresAt: 2_000_000, remaining: 80).health(at: now), .healthy)
    }

    private func account(expiresAt: Int?, ok: Bool = true, remaining: Double = 80) -> AccountSnapshot {
        AccountSnapshot(
            id: "2",
            name: "Codex 2",
            displayName: nil,
            email: nil,
            plan: "plus",
            subscriptionExpiresAt: expiresAt,
            ok: ok,
            error: nil,
            windows: [quotaWindow(remaining: remaining, resetsAt: 2_000_000)],
            resetCredits: 0,
            checkedAt: 0
        )
    }

    private func quotaWindow(remaining: Double, resetsAt: Int) -> QuotaWindow {
        QuotaWindow(
            label: "5 giờ",
            remainingPercent: remaining,
            usedPercent: 100 - remaining,
            resetsAt: resetsAt,
            windowMinutes: 300
        )
    }
}
