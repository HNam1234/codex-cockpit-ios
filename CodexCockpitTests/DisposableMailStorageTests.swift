import Foundation
import UserNotifications
import XCTest
@testable import CodexCockpit

final class DisposableMailStorageTests: XCTestCase {
    func testCredentialVaultReplacesDeletesAndUsesDeviceOnlyAccessibility() throws {
        let keychain = DisposableMailKeychainFake()
        let vault = DisposableMailCredentialVault(keychain: keychain)
        let mailboxID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let first = MailTMCredential(
            providerAccountID: "provider-account",
            address: "first@example.test",
            password: "first-password",
            token: "first-token"
        )
        let replacement = MailTMCredential(
            providerAccountID: "provider-account",
            address: "first@example.test",
            password: "replacement-password",
            token: "replacement-token"
        )

        try vault.save(first, mailboxID: mailboxID)
        try vault.save(replacement, mailboxID: mailboxID)

        XCTAssertEqual(try vault.credential(mailboxID: mailboxID), replacement)
        XCTAssertEqual(keychain.records.count, 1)
        XCTAssertEqual(keychain.records[0].account, mailboxID.uuidString.lowercased())
        XCTAssertEqual(keychain.records[0].accessibility, .whenUnlockedThisDeviceOnly)

        try vault.delete(mailboxID: mailboxID)
        XCTAssertNil(try vault.credential(mailboxID: mailboxID))
        XCTAssertTrue(keychain.records.isEmpty)
    }

    func testSnapshotRoundTripsAtomicallyWithoutCredentialsAndBoundsCachedMessages() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("mail-cache.json")
        let persistence = DisposableMailPersistence(
            fileURL: fileURL,
            maxMessagesPerMailbox: 3,
            maxBodyLength: 32
        )
        let mailbox = makeMailbox()
        let messages = (0..<5).map { offset in
            makeMessage(
                mailboxID: mailbox.id,
                id: "message-\(offset)",
                receivedAt: Date(timeIntervalSince1970: TimeInterval(1_900_000_000 + offset)),
                text: String(repeating: "x", count: 80)
            )
        }
        let snapshot = DisposableMailSnapshot(
            mailboxes: [mailbox],
            messagesByMailbox: [mailbox.id: messages]
        )

        try persistence.save(snapshot)
        let restored = try persistence.load()

        XCTAssertEqual(restored.mailboxes, [mailbox])
        XCTAssertEqual(restored.messagesByMailbox[mailbox.id]?.map(\.id), [
            "message-4", "message-3", "message-2"
        ])
        XCTAssertTrue(restored.messagesByMailbox[mailbox.id, default: []].allSatisfy {
            $0.text.count <= 32
        })
        let serialized = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(serialized.contains("known-password-fixture"))
        XCTAssertFalse(serialized.contains("known-token-fixture"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("tmp").path))
        XCTAssertTrue(
            DisposableMailPersistence.protectedWritingOptions.contains(.completeFileProtection),
            "Mailbox cache must remain protected while the device is locked"
        )
    }

    func testCorruptCacheRecoversToEmptySnapshot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("mail-cache.json")
        try Data("not-json".utf8).write(to: fileURL)
        let persistence = DisposableMailPersistence(fileURL: fileURL)

        XCTAssertEqual(try persistence.load(), .empty)
    }

    func testReminderSchedulerUsesStableSafeSevenAndOneDayRequests() async throws {
        let calendar = utcCalendar()
        let now = date(2030, 3, 1, calendar: calendar)
        let expiry = date(2030, 3, 31, calendar: calendar)
        let mailbox = makeMailbox(expiresAt: expiry)
        let center = DisposableMailNotificationCenterFake(status: .authorized)
        let scheduler = DisposableMailReminderScheduler(
            center: center,
            calendar: calendar,
            now: { now }
        )

        await scheduler.schedule(mailbox: mailbox)

        let expectedIDs = Set([
            DisposableMailReminderScheduler.identifier(mailboxID: mailbox.id, daysBefore: 7),
            DisposableMailReminderScheduler.identifier(mailboxID: mailbox.id, daysBefore: 1)
        ])
        XCTAssertEqual(Set(center.requests.map(\.identifier)), expectedIDs)
        XCTAssertEqual(center.removedIdentifiers.last.map(Set.init), expectedIDs)
        XCTAssertEqual(triggerDates(center.requests, calendar: calendar), Set([
            date(2030, 3, 24, calendar: calendar),
            date(2030, 3, 30, calendar: calendar)
        ]))
        XCTAssertTrue(center.requests.allSatisfy { request in
            let content = request.content
            return !content.title.contains(mailbox.address) &&
                !content.body.contains(mailbox.address) &&
                !content.body.localizedCaseInsensitiveContains("code") &&
                content.userInfo.isEmpty
        })

        var changed = mailbox
        changed = DisposableMailbox(
            id: changed.id,
            providerAccountID: changed.providerAccountID,
            address: changed.address,
            createdAt: changed.createdAt,
            expiresAt: date(2030, 4, 2, calendar: calendar),
            lifetime: changed.lifetime,
            linkedAccountID: changed.linkedAccountID,
            state: changed.state,
            unreadCount: changed.unreadCount,
            lastSyncedAt: changed.lastSyncedAt,
            errorCategory: changed.errorCategory
        )
        await scheduler.schedule(mailbox: changed)

        XCTAssertEqual(Set(center.requests.map(\.identifier)), expectedIDs)
        XCTAssertEqual(triggerDates(center.requests, calendar: calendar), Set([
            date(2030, 3, 26, calendar: calendar),
            date(2030, 4, 1, calendar: calendar)
        ]))

        scheduler.cancel(mailboxID: mailbox.id)
        XCTAssertEqual(center.removedIdentifiers.last.map(Set.init), expectedIDs)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testReminderSchedulerSkipsPastDatesAndPermissionDenialNeverThrows() async {
        let calendar = utcCalendar()
        let now = date(2030, 3, 30, calendar: calendar)
        let mailbox = makeMailbox(expiresAt: date(2030, 3, 31, calendar: calendar))
        let authorizedCenter = DisposableMailNotificationCenterFake(status: .authorized)
        let authorizedScheduler = DisposableMailReminderScheduler(
            center: authorizedCenter,
            calendar: calendar,
            now: { now }
        )

        await authorizedScheduler.schedule(mailbox: mailbox)
        XCTAssertTrue(authorizedCenter.requests.isEmpty)

        let deniedCenter = DisposableMailNotificationCenterFake(status: .denied)
        let deniedScheduler = DisposableMailReminderScheduler(
            center: deniedCenter,
            calendar: calendar,
            now: { now.addingTimeInterval(-20 * 86_400) }
        )
        await deniedScheduler.schedule(mailbox: mailbox)
        XCTAssertTrue(deniedCenter.requests.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DisposableMailStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeMailbox(
        expiresAt: Date = Date(timeIntervalSince1970: 1_900_000_000)
    ) -> DisposableMailbox {
        DisposableMailbox(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            providerAccountID: "provider-account",
            address: "mailbox@example.test",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: expiresAt,
            lifetime: .sixtyDays,
            linkedAccountID: "codex-account",
            state: .active,
            unreadCount: 2,
            lastSyncedAt: nil,
            errorCategory: nil
        )
    }

    private func makeMessage(
        mailboxID: UUID,
        id: String,
        receivedAt: Date,
        text: String
    ) -> DisposableMessage {
        DisposableMessage(
            id: id,
            mailboxID: mailboxID,
            senderName: "Sender",
            senderAddress: "sender@example.test",
            subject: "Subject",
            intro: "Intro",
            text: text,
            receivedAt: receivedAt,
            seen: false,
            attachments: []
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func triggerDates(
        _ requests: [UNNotificationRequest],
        calendar: Calendar
    ) -> Set<Date> {
        Set(requests.compactMap { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
            return calendar.date(from: trigger.dateComponents)
        })
    }
}

private final class DisposableMailKeychainFake: DisposableMailKeychainAccessing, @unchecked Sendable {
    struct Record: Equatable {
        let service: String
        let account: String
        let data: Data
        let accessibility: DisposableMailKeychainAccessibility
    }

    private let lock = NSLock()
    private var storage: [String: Record] = [:]

    var records: [Record] {
        lock.withLock { Array(storage.values) }
    }

    func data(service: String, account: String) throws -> Data? {
        lock.withLock { storage["\(service)|\(account)"]?.data }
    }

    func upsert(
        _ data: Data,
        service: String,
        account: String,
        accessibility: DisposableMailKeychainAccessibility
    ) throws {
        lock.withLock {
            storage["\(service)|\(account)"] = Record(
                service: service,
                account: account,
                data: data,
                accessibility: accessibility
            )
        }
    }

    func delete(service: String, account: String) throws {
        _ = lock.withLock { storage.removeValue(forKey: "\(service)|\(account)") }
    }
}

private final class DisposableMailNotificationCenterFake: DisposableMailNotificationCenterProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let status: UNAuthorizationStatus
    private var storage: [String: UNNotificationRequest] = [:]
    private var removals: [[String]] = []

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    var requests: [UNNotificationRequest] {
        lock.withLock { storage.values.sorted { $0.identifier < $1.identifier } }
    }

    var removedIdentifiers: [[String]] {
        lock.withLock { removals }
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func add(_ request: UNNotificationRequest) async throws {
        lock.withLock { storage[request.identifier] = request }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            removals.append(identifiers)
            identifiers.forEach { storage.removeValue(forKey: $0) }
        }
    }
}
