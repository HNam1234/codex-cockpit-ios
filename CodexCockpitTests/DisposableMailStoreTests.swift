import Foundation
import XCTest
@testable import CodexCockpit

@MainActor
final class DisposableMailStoreTests: XCTestCase {
    func testCreatePublishesOnlyAfterVaultAndPersistenceAndSchedulesDefaultLifetime() async {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let mailboxID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let provider = DisposableMailProviderFake()
        let vault = DisposableMailVaultFake()
        let persistence = DisposableMailPersistenceFake()
        let reminders = DisposableMailReminderFake()
        var store: DisposableMailStore!
        persistence.onSave = {
            XCTAssertTrue(store.mailboxes.isEmpty, "Mailbox must not appear before persistence succeeds")
        }
        store = DisposableMailStore(
            provider: provider,
            vault: vault,
            persistence: persistence,
            reminders: reminders,
            calendar: utcCalendar(),
            now: { now },
            makeID: { mailboxID }
        )

        let created = await store.create(lifetime: .default, linkedAccountID: "codex-account")

        let mailbox = try? XCTUnwrap(created)
        XCTAssertEqual(mailbox?.id, mailboxID)
        XCTAssertEqual(mailbox?.lifetime, .sixtyDays)
        XCTAssertEqual(mailbox?.expiresAt, MailboxLifetime.sixtyDays.expiry(from: now, calendar: utcCalendar()))
        XCTAssertEqual(mailbox?.linkedAccountID, "codex-account")
        XCTAssertEqual(store.mailboxes, mailbox.map { [$0] } ?? [])
        XCTAssertEqual(vault.saved[mailboxID]?.address, "candidate-1@example.test")
        XCTAssertEqual(persistence.snapshot.mailboxes, store.mailboxes)
        XCTAssertEqual(reminders.scheduled.map(\.id), [mailboxID])
        XCTAssertNil(store.errorMessage)
    }

    func testRefreshHonorsStaleWindowForceUnreadAndOneTokenRefresh() async {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        var mailbox = makeMailbox(lastSyncedAt: now.addingTimeInterval(-30))
        let oldCredential = credential(token: "old-token")
        let renewedCredential = credential(token: "new-token")
        let provider = DisposableMailProviderFake(
            authenticationResults: [.success(renewedCredential)],
            listResults: [
                .failure(.unauthorized),
                .success([
                    makeMessage(mailboxID: mailbox.id, id: "unread", seen: false),
                    makeMessage(mailboxID: mailbox.id, id: "seen", seen: true)
                ])
            ]
        )
        let vault = DisposableMailVaultFake(initial: [mailbox.id: oldCredential])
        let persistence = DisposableMailPersistenceFake(
            snapshot: DisposableMailSnapshot(mailboxes: [mailbox], messagesByMailbox: [:])
        )
        let store = makeStore(
            provider: provider,
            vault: vault,
            persistence: persistence,
            now: now
        )

        await store.refresh(mailboxID: mailbox.id, force: false)
        let callsBeforeForce = await provider.listCallCount()
        XCTAssertEqual(callsBeforeForce, 0)

        await store.refresh(mailboxID: mailbox.id, force: true)

        mailbox = try! XCTUnwrap(store.mailboxes.first)
        let listCalls = await provider.listCallCount()
        let authenticationCalls = await provider.authenticationCallCount()
        XCTAssertEqual(listCalls, 2)
        XCTAssertEqual(authenticationCalls, 1)
        XCTAssertEqual(vault.saved[mailbox.id], renewedCredential)
        XCTAssertEqual(mailbox.unreadCount, 1)
        XCTAssertEqual(mailbox.lastSyncedAt, now)
        XCTAssertEqual(store.messagesByMailbox[mailbox.id]?.count, 2)
        XCTAssertNil(mailbox.errorCategory)
    }

    func testLoadMessageMarksItSeenAndUpdatesCachedDetail() async {
        let mailbox = makeMailbox()
        let detail = makeMessage(mailboxID: mailbox.id, id: "detail", seen: false, text: "Code 482731")
        let provider = DisposableMailProviderFake(messageResults: [.success(detail)])
        let vault = DisposableMailVaultFake(initial: [mailbox.id: credential()])
        let persistence = DisposableMailPersistenceFake(
            snapshot: DisposableMailSnapshot(
                mailboxes: [mailbox],
                messagesByMailbox: [mailbox.id: [makeMessage(mailboxID: mailbox.id, id: "detail", seen: false)]]
            )
        )
        let store = makeStore(provider: provider, vault: vault, persistence: persistence)

        let loaded = await store.loadMessage(mailboxID: mailbox.id, messageID: "detail")

        XCTAssertEqual(loaded?.text, "Code 482731")
        XCTAssertEqual(loaded?.seen, true)
        XCTAssertEqual(store.messagesByMailbox[mailbox.id]?.first?.seen, true)
        let markedSeenIDs = await provider.markedSeenIDs()
        XCTAssertEqual(markedSeenIDs, ["detail"])
    }

    func testRefreshFailuresPreserveCacheAndExposeOnlySafeState() async {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let mailbox = makeMailbox(lastSyncedAt: now.addingTimeInterval(-120))
        let cached = makeMessage(mailboxID: mailbox.id, id: "cached", seen: false)
        let retryAt = now.addingTimeInterval(90)
        let provider = DisposableMailProviderFake(listResults: [
            .failure(.offline),
            .failure(.rateLimited(retryAt: retryAt)),
            .failure(.missing)
        ])
        let vault = DisposableMailVaultFake(initial: [mailbox.id: credential()])
        let persistence = DisposableMailPersistenceFake(
            snapshot: DisposableMailSnapshot(
                mailboxes: [mailbox],
                messagesByMailbox: [mailbox.id: [cached]]
            )
        )
        let store = makeStore(provider: provider, vault: vault, persistence: persistence, now: now)

        await store.refresh(mailboxID: mailbox.id, force: true)
        XCTAssertEqual(store.messagesByMailbox[mailbox.id], [cached])
        XCTAssertEqual(store.mailboxes.first?.errorCategory, .offline)
        XCTAssertFalse(store.errorMessage?.contains("secret-token") == true)
        XCTAssertFalse(store.errorMessage?.contains("secret-password") == true)

        await store.refresh(mailboxID: mailbox.id, force: true)
        XCTAssertEqual(store.retryAt, retryAt)
        XCTAssertEqual(store.messagesByMailbox[mailbox.id], [cached])

        await store.refresh(mailboxID: mailbox.id, force: true)
        XCTAssertEqual(store.mailboxes.first?.state, .providerUnavailable)
        XCTAssertEqual(store.messagesByMailbox[mailbox.id], [cached])
    }

    func testPartialCreateCleansUpAfterAuthenticationVaultAndPersistenceFailures() async {
        let cleanupCredential = credential(token: "cleanup-token")
        let authenticationProvider = DisposableMailProviderFake(authenticationResults: [
            .failure(.unavailable),
            .success(cleanupCredential)
        ])
        let authStore = makeStore(provider: authenticationProvider)

        let authenticationFailure = await authStore.create(lifetime: .sixtyDays, linkedAccountID: nil)
        let authenticationDeletes = await authenticationProvider.deletedAccountIDs()
        XCTAssertNil(authenticationFailure)
        XCTAssertTrue(authStore.mailboxes.isEmpty)
        XCTAssertEqual(authenticationDeletes, ["provider-account"])

        let vaultProvider = DisposableMailProviderFake()
        let failingVault = DisposableMailVaultFake()
        failingVault.failSave = true
        let vaultStore = makeStore(provider: vaultProvider, vault: failingVault)
        let vaultFailure = await vaultStore.create(lifetime: .sixtyDays, linkedAccountID: nil)
        let vaultDeletes = await vaultProvider.deletedAccountIDs()
        XCTAssertNil(vaultFailure)
        XCTAssertTrue(vaultStore.mailboxes.isEmpty)
        XCTAssertEqual(vaultDeletes, ["provider-account"])

        let persistenceProvider = DisposableMailProviderFake()
        let rollbackVault = DisposableMailVaultFake()
        let failingPersistence = DisposableMailPersistenceFake()
        failingPersistence.failSave = true
        let persistenceStore = makeStore(
            provider: persistenceProvider,
            vault: rollbackVault,
            persistence: failingPersistence
        )
        let persistenceFailure = await persistenceStore.create(lifetime: .sixtyDays, linkedAccountID: nil)
        let persistenceDeletes = await persistenceProvider.deletedAccountIDs()
        XCTAssertNil(persistenceFailure)
        XCTAssertTrue(persistenceStore.mailboxes.isEmpty)
        XCTAssertTrue(rollbackVault.saved.isEmpty)
        XCTAssertEqual(persistenceDeletes, ["provider-account"])
    }

    func testCreateRetriesOnlyBoundedAddressConflicts() async {
        let provider = DisposableMailProviderFake(createResults: [
            .failure(.conflict),
            .failure(.conflict),
            .success(MailTMAccount(
                id: "provider-account",
                address: "candidate-3@example.test",
                isDisabled: false,
                isDeleted: false
            ))
        ])
        let store = makeStore(provider: provider)

        let mailbox = await store.create(lifetime: .thirtyDays, linkedAccountID: nil)

        let seedCalls = await provider.seedCallCount()
        let createCalls = await provider.createCallCount()
        XCTAssertEqual(mailbox?.address, "candidate-3@example.test")
        XCTAssertEqual(seedCalls, 3)
        XCTAssertEqual(createCalls, 3)
    }

    func testMappingRequiresExplicitReplacementAndAccountUnlinkKeepsMailbox() {
        var first = makeMailbox(id: "11111111-1111-4111-8111-111111111111", linkedAccountID: "account-a")
        let second = makeMailbox(id: "22222222-2222-4222-8222-222222222222")
        let persistence = DisposableMailPersistenceFake(
            snapshot: DisposableMailSnapshot(mailboxes: [first, second], messagesByMailbox: [:])
        )
        let reminders = DisposableMailReminderFake()
        let store = makeStore(persistence: persistence, reminders: reminders)

        store.link(mailboxID: second.id, toAccountID: "account-a", replacement: nil)
        XCTAssertEqual(store.mailbox(linkedTo: "account-a")?.id, first.id)
        XCTAssertNotNil(store.errorMessage)

        store.link(mailboxID: second.id, toAccountID: "account-a", replacement: .keepExistingUnlinked)
        XCTAssertNil(store.mailboxes.first(where: { $0.id == first.id })?.linkedAccountID)
        XCTAssertEqual(store.mailbox(linkedTo: "account-a")?.id, second.id)

        store.unlinkAccount("account-a")
        XCTAssertNil(store.mailbox(linkedTo: "account-a"))
        XCTAssertEqual(store.mailboxes.count, 2)

        first.linkedAccountID = "account-b"
        persistence.snapshot = DisposableMailSnapshot(mailboxes: [first, second], messagesByMailbox: [:])
        let deleteReplacementStore = makeStore(persistence: persistence, reminders: reminders)
        deleteReplacementStore.link(
            mailboxID: second.id,
            toAccountID: "account-b",
            replacement: .deleteExisting
        )
        XCTAssertEqual(
            deleteReplacementStore.mailboxes.first(where: { $0.id == first.id })?.state,
            .pendingDeletion
        )
        XCTAssertEqual(deleteReplacementStore.mailbox(linkedTo: "account-b")?.id, second.id)
        XCTAssertTrue(reminders.cancelled.contains(first.id))
    }

    func testExpiryDeletionOfflineTombstoneRetryMissingAndForgetLocally() async {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let expired = makeMailbox(expiresAt: now.addingTimeInterval(-1), linkedAccountID: "account-a")
        let cached = makeMessage(mailboxID: expired.id, id: "cached", seen: false)
        let provider = DisposableMailProviderFake(deleteResults: [
            .failure(.offline),
            .success(())
        ])
        let vault = DisposableMailVaultFake(initial: [expired.id: credential()])
        let persistence = DisposableMailPersistenceFake(
            snapshot: DisposableMailSnapshot(
                mailboxes: [expired],
                messagesByMailbox: [expired.id: [cached]]
            )
        )
        let reminders = DisposableMailReminderFake()
        let store = makeStore(
            provider: provider,
            vault: vault,
            persistence: persistence,
            reminders: reminders,
            now: now
        )

        await store.handleForeground(validAccountIDs: ["account-a"])
        XCTAssertEqual(store.mailboxes.first?.state, .pendingDeletion)
        XCTAssertTrue(store.activeMailboxes.isEmpty)
        XCTAssertNotNil(vault.saved[expired.id])
        XCTAssertEqual(store.messagesByMailbox[expired.id], [cached])
        XCTAssertTrue(reminders.cancelled.contains(expired.id))

        await store.retryPendingDeletions()
        XCTAssertTrue(store.mailboxes.isEmpty)
        XCTAssertNil(vault.saved[expired.id])
        XCTAssertNil(store.messagesByMailbox[expired.id])

        let missingMailbox = makeMailbox(id: "33333333-3333-4333-8333-333333333333")
        let missingProvider = DisposableMailProviderFake(deleteResults: [.failure(.missing)])
        let missingVault = DisposableMailVaultFake(initial: [missingMailbox.id: credential()])
        let missingPersistence = DisposableMailPersistenceFake(
            snapshot: DisposableMailSnapshot(mailboxes: [missingMailbox], messagesByMailbox: [:])
        )
        let missingStore = makeStore(
            provider: missingProvider,
            vault: missingVault,
            persistence: missingPersistence
        )
        await missingStore.delete(mailboxID: missingMailbox.id)
        XCTAssertTrue(missingStore.mailboxes.isEmpty)

        let forgotten = makeMailbox(id: "44444444-4444-4444-8444-444444444444")
        let forgetVault = DisposableMailVaultFake(initial: [forgotten.id: credential()])
        let forgetPersistence = DisposableMailPersistenceFake(
            snapshot: DisposableMailSnapshot(mailboxes: [forgotten], messagesByMailbox: [:])
        )
        let forgetReminders = DisposableMailReminderFake()
        let forgetStore = makeStore(
            vault: forgetVault,
            persistence: forgetPersistence,
            reminders: forgetReminders
        )
        forgetStore.forgetLocally(mailboxID: forgotten.id)
        XCTAssertTrue(forgetStore.mailboxes.isEmpty)
        XCTAssertNil(forgetVault.saved[forgotten.id])
        XCTAssertTrue(forgetReminders.cancelled.contains(forgotten.id))
    }

    private func makeStore(
        provider: DisposableMailProviderFake = DisposableMailProviderFake(),
        vault: DisposableMailVaultFake = DisposableMailVaultFake(),
        persistence: DisposableMailPersistenceFake = DisposableMailPersistenceFake(),
        reminders: DisposableMailReminderFake = DisposableMailReminderFake(),
        now: Date = Date(timeIntervalSince1970: 1_900_000_000)
    ) -> DisposableMailStore {
        DisposableMailStore(
            provider: provider,
            vault: vault,
            persistence: persistence,
            reminders: reminders,
            calendar: utcCalendar(),
            now: { now },
            makeID: { UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")! }
        )
    }

    private func makeMailbox(
        id: String = "11111111-1111-4111-8111-111111111111",
        expiresAt: Date = Date(timeIntervalSince1970: 2_000_000_000),
        linkedAccountID: String? = nil,
        lastSyncedAt: Date? = nil
    ) -> DisposableMailbox {
        DisposableMailbox(
            id: UUID(uuidString: id)!,
            providerAccountID: "provider-account",
            address: "candidate@example.test",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: expiresAt,
            lifetime: .sixtyDays,
            linkedAccountID: linkedAccountID,
            state: .active,
            unreadCount: 0,
            lastSyncedAt: lastSyncedAt,
            errorCategory: nil
        )
    }

    private func makeMessage(
        mailboxID: UUID,
        id: String,
        seen: Bool,
        text: String = "Cached body"
    ) -> DisposableMessage {
        DisposableMessage(
            id: id,
            mailboxID: mailboxID,
            senderName: nil,
            senderAddress: "sender@example.test",
            subject: "Subject",
            intro: "Intro",
            text: text,
            receivedAt: Date(timeIntervalSince1970: 1_850_000_000),
            seen: seen,
            attachments: []
        )
    }

    private func credential(token: String = "secret-token") -> MailTMCredential {
        MailTMCredential(
            providerAccountID: "provider-account",
            address: "candidate@example.test",
            password: "secret-password",
            token: token
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private actor DisposableMailProviderFake: DisposableMailServing {
    private var createResults: [Result<MailTMAccount, DisposableMailServiceError>]
    private var authenticationResults: [Result<MailTMCredential, DisposableMailServiceError>]
    private var listResults: [Result<[DisposableMessage], DisposableMailServiceError>]
    private var messageResults: [Result<DisposableMessage, DisposableMailServiceError>]
    private var deleteResults: [Result<Void, DisposableMailServiceError>]
    private var seeds = 0
    private var creates = 0
    private var authentications = 0
    private var lists = 0
    private var marked: [String] = []
    private var deleted: [String] = []

    init(
        createResults: [Result<MailTMAccount, DisposableMailServiceError>] = [],
        authenticationResults: [Result<MailTMCredential, DisposableMailServiceError>] = [],
        listResults: [Result<[DisposableMessage], DisposableMailServiceError>] = [],
        messageResults: [Result<DisposableMessage, DisposableMailServiceError>] = [],
        deleteResults: [Result<Void, DisposableMailServiceError>] = []
    ) {
        self.createResults = createResults
        self.authenticationResults = authenticationResults
        self.listResults = listResults
        self.messageResults = messageResults
        self.deleteResults = deleteResults
    }

    func availableDomains() async throws -> [MailTMDomain] {
        [MailTMDomain(id: "domain", domain: "example.test", isActive: true, isPrivate: false)]
    }

    func makeAccountSeed(domain: String) async throws -> MailTMAccountSeed {
        seeds += 1
        return MailTMAccountSeed(
            address: "candidate-\(seeds)@\(domain)",
            password: "generated-secret-\(seeds)"
        )
    }

    func createAccount(address: String, password: String) async throws -> MailTMAccount {
        creates += 1
        if !createResults.isEmpty { return try createResults.removeFirst().get() }
        return MailTMAccount(
            id: "provider-account",
            address: address,
            isDisabled: false,
            isDeleted: false
        )
    }

    func authenticate(address: String, password: String) async throws -> MailTMCredential {
        authentications += 1
        if !authenticationResults.isEmpty { return try authenticationResults.removeFirst().get() }
        return MailTMCredential(
            providerAccountID: "provider-account",
            address: address,
            password: password,
            token: "provider-token"
        )
    }

    func listMessages(mailboxID: UUID, token: String) async throws -> [DisposableMessage] {
        lists += 1
        if !listResults.isEmpty { return try listResults.removeFirst().get() }
        return []
    }

    func message(mailboxID: UUID, messageID: String, token: String) async throws -> DisposableMessage {
        if !messageResults.isEmpty { return try messageResults.removeFirst().get() }
        throw DisposableMailServiceError.missing
    }

    func markSeen(messageID: String, token: String) async throws {
        marked.append(messageID)
    }

    func deleteAccount(accountID: String, token: String) async throws {
        deleted.append(accountID)
        if !deleteResults.isEmpty { _ = try deleteResults.removeFirst().get() }
    }

    func seedCallCount() -> Int { seeds }
    func createCallCount() -> Int { creates }
    func authenticationCallCount() -> Int { authentications }
    func listCallCount() -> Int { lists }
    func markedSeenIDs() -> [String] { marked }
    func deletedAccountIDs() -> [String] { deleted }
}

private final class DisposableMailVaultFake: DisposableMailCredentialVaultProtocol, @unchecked Sendable {
    var saved: [UUID: MailTMCredential]
    var failSave = false

    init(initial: [UUID: MailTMCredential] = [:]) {
        saved = initial
    }

    func save(_ credential: MailTMCredential, mailboxID: UUID) throws {
        if failSave { throw DisposableMailCredentialVaultError.keychainFailure(-1) }
        saved[mailboxID] = credential
    }

    func credential(mailboxID: UUID) throws -> MailTMCredential? {
        saved[mailboxID]
    }

    func delete(mailboxID: UUID) throws {
        saved.removeValue(forKey: mailboxID)
    }
}

private final class DisposableMailPersistenceFake: DisposableMailPersisting, @unchecked Sendable {
    var snapshot: DisposableMailSnapshot
    var failSave = false
    var onSave: (() -> Void)?

    init(snapshot: DisposableMailSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func load() throws -> DisposableMailSnapshot { snapshot }

    func save(_ snapshot: DisposableMailSnapshot) throws {
        onSave?()
        if failSave { throw CocoaError(.fileWriteUnknown) }
        self.snapshot = snapshot
    }
}

private final class DisposableMailReminderFake: DisposableMailReminderScheduling, @unchecked Sendable {
    var scheduled: [DisposableMailbox] = []
    var cancelled: [UUID] = []

    func schedule(mailbox: DisposableMailbox) async {
        scheduled.append(mailbox)
    }

    func cancel(mailboxID: UUID) {
        cancelled.append(mailboxID)
    }
}
