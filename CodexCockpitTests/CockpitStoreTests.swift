import XCTest
@testable import CodexCockpit

@MainActor
final class CockpitStoreTests: XCTestCase {
    func testImportDirectOAuthReplacesMappedRemoteAccountWithLiveQuota() async throws {
        let initial = AccountSnapshot(
            id: "1",
            name: "Codex 1",
            displayName: nil,
            email: nil,
            plan: nil,
            subscriptionExpiresAt: nil,
            ok: false,
            error: "Cần đăng nhập",
            windows: [],
            resetCredits: 0,
            checkedAt: 100
        )
        let api = CockpitAPIStub(accounts: [initial])
        let store = CockpitStore(api: api)
        await store.load()
        let registration = DirectOAuthRegistration(
            profileID: "3",
            clientID: "client_1234567890",
            subject: "user-123",
            email: "person@example.com",
            name: "Person",
            idToken: "header.payload.signature",
            accessToken: "access.payload.signature",
            refreshToken: "refresh-token-value",
            tokenType: "Bearer",
            scopes: ["openid", "offline_access"],
            expiresAt: 2_000_000_000,
            earliestRefreshAt: nil
        )

        let imported = await store.importDirectOAuth(accountID: "1", registration: registration)

        XCTAssertEqual(imported?.id, "1")
        XCTAssertEqual(store.account(id: "1")?.email, "person@example.com")
        XCTAssertEqual(store.account(id: "1")?.windows.first?.remainingPercent, 88)
        let capturedRequest = await api.importRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.accountID, "1")
        XCTAssertEqual(request.profileID, "3")
        XCTAssertNil(store.errorMessage)
    }

    func testOAuthRecoveryOnlyTargetsBrokenRemoteAccounts() async {
        let api = CockpitAPIStub(accounts: [
            account(id: "1", displayName: "Healthy", remaining: 75),
            AccountSnapshot(
                id: "2",
                name: "Codex 2",
                displayName: nil,
                email: nil,
                plan: nil,
                subscriptionExpiresAt: nil,
                ok: false,
                error: "Cần đăng nhập",
                windows: [],
                resetCredits: 0,
                checkedAt: 100
            )
        ])
        let store = CockpitStore(api: api)
        await store.load()

        let registration = directRegistration()
        XCTAssertFalse(store.needsDirectOAuthRecovery(accountID: "1", registration: registration))
        XCTAssertTrue(store.needsDirectOAuthRecovery(accountID: "2", registration: registration))
        XCTAssertFalse(store.needsDirectOAuthRecovery(accountID: "local:legacy", registration: registration))
        XCTAssertFalse(store.needsDirectOAuthRecovery(accountID: "missing", registration: registration))
    }

    func testSuccessfulOAuthImportIsNotReplayedAfterTheVPSSlotLaterBreaks() async throws {
        let suiteName = "CockpitStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let broken = AccountSnapshot(
            id: "1",
            name: "Codex 1",
            displayName: nil,
            email: nil,
            plan: nil,
            subscriptionExpiresAt: nil,
            ok: false,
            error: "Cần đăng nhập",
            windows: [],
            resetCredits: 0,
            checkedAt: 100
        )
        let api = CockpitAPIStub(accounts: [broken])
        let registration = directRegistration()
        var store: CockpitStore? = CockpitStore(api: api, defaults: defaults)
        await store?.load()

        let imported = await store?.importDirectOAuth(accountID: "1", registration: registration)
        XCTAssertNotNil(imported)
        store = CockpitStore(api: api, defaults: defaults)
        await store?.load()

        XCTAssertFalse(store?.needsDirectOAuthRecovery(accountID: "1", registration: registration) ?? true)
    }

    func testRefreshAllRequestsEveryVisibleAccountAndReplacesQuotaSnapshots() async {
        let initialAccounts = [
            account(id: "1", displayName: "Old One", remaining: 10),
            account(id: "2", displayName: "Old Two", remaining: 20)
        ]
        let api = CockpitAPIStub(accounts: initialAccounts)
        let store = CockpitStore(api: api)
        await store.load()

        await store.refreshAll()

        let requestedAccountIDs = await api.requestedAccountIDs()
        XCTAssertEqual(Set(requestedAccountIDs), Set(["1", "2"]))
        XCTAssertEqual(store.accounts.compactMap(\.displayName), ["Fresh 1", "Fresh 2"])
        XCTAssertEqual(store.accounts.flatMap(\.windows).map(\.remainingPercent), [91, 92])
        XCTAssertNil(store.errorMessage)
    }

    func testVPSDeviceAuthorizationReturnsCodeThenPublishesQuotaSnapshot() async throws {
        let broken = AccountSnapshot(
            id: "3",
            name: "Codex 3",
            displayName: nil,
            email: nil,
            plan: nil,
            subscriptionExpiresAt: nil,
            ok: false,
            error: "Cần đăng nhập",
            windows: [],
            resetCredits: 0,
            checkedAt: 100
        )
        let connected = account(id: "3", displayName: "Device User", remaining: 73)
        let waiting = LoginSession(
            sessionID: "session-3",
            accountID: "3",
            status: "waiting",
            verificationURL: "https://auth.openai.com/codex/device",
            userCode: "ABCD-EFGH",
            expiresAt: 2_000_000_000,
            error: nil,
            account: nil
        )
        let succeeded = LoginSession(
            sessionID: "session-3",
            accountID: "3",
            status: "succeeded",
            verificationURL: nil,
            userCode: nil,
            expiresAt: 2_000_000_000,
            error: nil,
            account: connected
        )
        let api = CockpitAPIStub(
            accounts: [broken],
            authorizationStart: waiting,
            authorizationStatuses: [succeeded]
        )
        let store = CockpitStore(api: api, loginPollInterval: .milliseconds(1))
        await store.load()

        let session = await store.beginReauthorization(accountID: "3")
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(session?.userCode, "ABCD-EFGH")
        let startedIDs = await api.startedAuthorizationIDs()
        XCTAssertEqual(startedIDs, ["3"])
        XCTAssertEqual(store.account(id: "3")?.email, "user3@example.com")
        XCTAssertEqual(store.account(id: "3")?.windows.first?.remainingPercent, 73)
        XCTAssertEqual(store.loginSessions["3"]?.status, "succeeded")
        XCTAssertNil(store.errorMessage)
    }

    func testLocalAccountUsesVerifiedEmailAndDoesNotCallServerRefresh() async throws {
        let suiteName = "CockpitStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let api = CockpitAPIStub(accounts: [])
        let store = CockpitStore(api: api, defaults: defaults)

        let pending = store.createLocalAccount()
        XCTAssertTrue(pending.isLocalDirect)
        XCTAssertFalse(pending.ok)

        store.completeLocalOAuth(accountID: pending.id, email: "Person@Example.com")
        let connected = try XCTUnwrap(store.account(id: pending.id))
        XCTAssertEqual(connected.email, "person@example.com")
        XCTAssertEqual(connected.identity, "person@example.com")
        XCTAssertEqual(connected.health(), .healthy)

        store.disconnectLocalOAuth(accountID: pending.id)
        let disconnected = try XCTUnwrap(store.account(id: pending.id))
        XCTAssertFalse(disconnected.ok)
        XCTAssertEqual(disconnected.health(), .needsLogin)

        await store.refreshAll()
        let requestedAccountIDs = await api.requestedAccountIDs()
        XCTAssertTrue(requestedAccountIDs.isEmpty)
    }

    private func account(id: String, displayName: String, remaining: Double) -> AccountSnapshot {
        AccountSnapshot(
            id: id,
            name: "Codex \(id)",
            displayName: displayName,
            email: "user\(id)@example.com",
            plan: "plus",
            subscriptionExpiresAt: 2_000_000_000,
            ok: true,
            error: nil,
            windows: [QuotaWindow(
                label: "5 giờ",
                remainingPercent: remaining,
                usedPercent: 100 - remaining,
                resetsAt: 2_000_000_000,
                windowMinutes: 300
            )],
            resetCredits: 0,
            checkedAt: 100
        )
    }

    private func directRegistration() -> DirectOAuthRegistration {
        DirectOAuthRegistration(
            profileID: "1",
            clientID: "client_1234567890",
            subject: "user-123",
            email: "person@example.com",
            name: "Person",
            idToken: "header.payload.signature",
            accessToken: "access.payload.signature",
            refreshToken: "refresh-token-value",
            tokenType: "Bearer",
            scopes: ["openid", "offline_access"],
            expiresAt: 2_000_000_000,
            earliestRefreshAt: nil
        )
    }
}

private actor CockpitAPIStub: CockpitAPIClient {
    private let initialAccounts: [AccountSnapshot]
    private let authorizationStart: LoginSession?
    private var authorizationStatuses: [LoginSession]
    private var requestedIDs: [String] = []
    private var startedAuthorizationAccountIDs: [String] = []
    private var importedRequest: (accountID: String, profileID: String)?

    init(
        accounts: [AccountSnapshot],
        authorizationStart: LoginSession? = nil,
        authorizationStatuses: [LoginSession] = []
    ) {
        initialAccounts = accounts
        self.authorizationStart = authorizationStart
        self.authorizationStatuses = authorizationStatuses
    }

    func requestedAccountIDs() -> [String] { requestedIDs }
    func importRequest() -> (accountID: String, profileID: String)? { importedRequest }
    func startedAuthorizationIDs() -> [String] { startedAuthorizationAccountIDs }

    func status() async throws -> NativeStatusResponse {
        NativeStatusResponse(
            generatedAt: 100,
            updatedAt: 100,
            pollSeconds: 900,
            capabilities: AppCapabilities(
                reauthorize: true,
                refreshUsage: true,
                resetCredit: false,
                dynamicProfiles: true,
                manageAccounts: true
            ),
            tiboReset: nil,
            accounts: initialAccounts
        )
    }

    func refresh(accountID: String) async throws -> AccountSnapshot {
        requestedIDs.append(accountID)
        let remaining = 90 + Double(Int(accountID) ?? 0)
        return AccountSnapshot(
            id: accountID,
            name: "Codex \(accountID)",
            displayName: "Fresh \(accountID)",
            email: "user\(accountID)@example.com",
            plan: "plus",
            subscriptionExpiresAt: 2_000_000_000,
            ok: true,
            error: nil,
            windows: [QuotaWindow(
                label: "5 giờ",
                remainingPercent: remaining,
                usedPercent: 100 - remaining,
                resetsAt: 2_000_000_000,
                windowMinutes: 300
            )],
            resetCredits: 0,
            checkedAt: 200
        )
    }

    func startAuthorization(accountID: String) async throws -> LoginSession {
        startedAuthorizationAccountIDs.append(accountID)
        guard let authorizationStart else { throw StubError.unused }
        return authorizationStart
    }

    func authorizationStatus(sessionID: String) async throws -> LoginSession {
        guard !authorizationStatuses.isEmpty else { throw StubError.unused }
        return authorizationStatuses.removeFirst()
    }

    func importDirectOAuth(
        accountID: String,
        registration: DirectOAuthRegistration
    ) async throws -> AccountSnapshot {
        importedRequest = (accountID, registration.profileID)
        return AccountSnapshot(
            id: accountID,
            name: "Codex \(accountID)",
            displayName: "Person",
            email: registration.email,
            plan: "plus",
            subscriptionExpiresAt: 2_000_000_000,
            ok: true,
            error: nil,
            windows: [QuotaWindow(
                label: "5 giờ",
                remainingPercent: 88,
                usedPercent: 12,
                resetsAt: 2_000_000_000,
                windowMinutes: 300
            )],
            resetCredits: 0,
            checkedAt: 300
        )
    }

    func consumeResetCredit(accountID: String, idempotencyKey: String) async throws -> ResetCreditResult {
        throw StubError.unused
    }

    func createAccount(name: String) async throws -> AccountSnapshot {
        throw StubError.unused
    }

    func deleteAccount(accountID: String) async throws {
        throw StubError.unused
    }

    private enum StubError: Error { case unused }
}
