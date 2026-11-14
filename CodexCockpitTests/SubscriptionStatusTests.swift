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

        XCTAssertEqual(account(expiresAt: 1_000_000 + Int(2.1 * 86_400)).subscriptionRemainingText(at: now), "Còn 3 ngày")
        XCTAssertEqual(account(expiresAt: 1_000_000 + Int(23.1 * 3_600)).subscriptionRemainingText(at: now), "Còn 24 giờ")
        XCTAssertEqual(account(expiresAt: 1_000_000 + 1_800).subscriptionRemainingText(at: now), "Còn <1 giờ")
    }

    func testExpiredSubscriptionIsExplicit() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let account = account(expiresAt: 999_999)

        XCTAssertEqual(account.subscriptionRemainingText(at: now), "Đã hết hạn")
        XCTAssertTrue(account.subscriptionIsExpired(at: now))
    }

    private func account(expiresAt: Int?) -> AccountSnapshot {
        AccountSnapshot(
            id: "2",
            name: "Codex 2",
            displayName: nil,
            email: nil,
            plan: "plus",
            subscriptionExpiresAt: expiresAt,
            ok: true,
            error: nil,
            windows: [],
            resetCredits: 0,
            checkedAt: 0
        )
    }
}
