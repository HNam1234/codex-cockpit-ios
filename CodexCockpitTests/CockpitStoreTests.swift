import XCTest
@testable import CodexCockpit

@MainActor
final class CockpitStoreTests: XCTestCase {
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
}

private actor CockpitAPIStub: CockpitAPIClient {
    private let initialAccounts: [AccountSnapshot]
    private var requestedIDs: [String] = []

    init(accounts: [AccountSnapshot]) {
        initialAccounts = accounts
    }

    func requestedAccountIDs() -> [String] { requestedIDs }

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
        throw StubError.unused
    }

    func authorizationStatus(sessionID: String) async throws -> LoginSession {
        throw StubError.unused
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
