import XCTest
@testable import CodexCockpit

final class DisposableMailModelTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDefaultLifetimeExpiresAfterSixtyCalendarDays() throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-31T12:00:00Z"))

        XCTAssertEqual(MailboxLifetime.default, .sixtyDays)
        XCTAssertEqual(
            MailboxLifetime.default.expiry(from: start, calendar: utcCalendar),
            ISO8601DateFormatter().date(from: "2026-04-01T12:00:00Z")
        )
    }

    func testThirtyDayLifetimeUsesCalendarDaysAcrossDaylightSavingChange() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-01T20:00:00Z"))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-31T19:00:00Z"))

        XCTAssertEqual(MailboxLifetime.thirtyDays.expiry(from: start, calendar: losAngeles), expected)
    }

    func testUnsupportedLifetimeCannotDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(MailboxLifetime.self, from: Data("45".utf8)))
    }

    func testRemainingDaysNeverBecomesNegative() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mailbox = sampleMailbox(expiresAt: now.addingTimeInterval(-3600))

        XCTAssertEqual(mailbox.remainingDays(at: now), 0)
    }

    func testEncodedMailboxAndMessageContainNoCredentialFields() throws {
        let mailbox = sampleMailbox(expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
        let message = DisposableMessage(
            id: "message-1",
            mailboxID: mailbox.id,
            senderName: "OpenAI",
            senderAddress: "noreply@example.com",
            subject: "Verification code",
            intro: "Your code",
            text: "Use 482731",
            receivedAt: Date(timeIntervalSince1970: 1_800_000_100),
            seen: false,
            attachments: [DisposableAttachment(
                id: "attachment-1",
                fileName: "notice.txt",
                mediaType: "text/plain",
                size: 42
            )]
        )
        let encoder = JSONEncoder()
        let encoded = String(data: try encoder.encode([mailbox]), encoding: .utf8)! +
            String(data: try encoder.encode([message]), encoding: .utf8)!

        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(encoded.contains("secret-password-fixture"))
        XCTAssertFalse(encoded.contains("secret-token-fixture"))
    }

    private func sampleMailbox(expiresAt: Date) -> DisposableMailbox {
        DisposableMailbox(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            providerAccountID: "provider-1",
            address: "sample@example.com",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: expiresAt,
            lifetime: .sixtyDays,
            linkedAccountID: "local:account-1",
            state: .active,
            unreadCount: 1,
            lastSyncedAt: nil,
            errorCategory: nil
        )
    }
}
