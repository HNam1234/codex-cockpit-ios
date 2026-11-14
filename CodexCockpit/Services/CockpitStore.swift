import Foundation

@MainActor
final class CockpitStore: ObservableObject {
    @Published private(set) var accounts: [AccountSnapshot] = []
    @Published private(set) var capabilities: AppCapabilities?
    @Published private(set) var tiboReset: TiboResetStatus?
    @Published private(set) var updatedAt: Int = 0
    @Published private(set) var pollSeconds = 900
    @Published private(set) var isLoading = false
    @Published private(set) var busyAccounts: Set<String> = []
    @Published private(set) var loginSessions: [String: LoginSession] = [:]
    @Published private(set) var isCreatingAccount = false
    @Published var errorMessage: String?

    private let api: any CockpitAPIClient
    private var loginTasks: [String: Task<Void, Never>] = [:]

    init(api: any CockpitAPIClient = CockpitAPI.shared) {
        self.api = api
    }

    func account(id: String) -> AccountSnapshot? {
        accounts.first(where: { $0.id == id })
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.status()
            accounts = response.accounts
            capabilities = response.capabilities
            tiboReset = response.tiboReset
            updatedAt = response.updatedAt
            pollSeconds = Self.clampedPollSeconds(response.pollSeconds)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        loginTasks.values.forEach { $0.cancel() }
        loginTasks = [:]
        accounts = []
        capabilities = nil
        tiboReset = nil
        updatedAt = 0
        loginSessions = [:]
        busyAccounts = []
        errorMessage = nil
    }

    func refreshAll() async {
        guard !isLoading else { return }
        let accountIDs = accounts.map(\.id)
        guard !accountIDs.isEmpty else {
            await load()
            return
        }

        isLoading = true
        busyAccounts.formUnion(accountIDs)
        defer {
            busyAccounts.subtract(accountIDs)
            isLoading = false
        }

        let api = self.api
        var refreshed: [AccountSnapshot] = []
        var failureCount = 0
        await withTaskGroup(of: AccountSnapshot?.self) { group in
            for accountID in accountIDs {
                group.addTask {
                    try? await api.refresh(accountID: accountID)
                }
            }
            for await account in group {
                if let account {
                    refreshed.append(account)
                } else {
                    failureCount += 1
                }
            }
        }

        refreshed.forEach(replace)
        errorMessage = failureCount == 0
            ? nil
            : L10n.format("error.refresh_partial", failureCount, accountIDs.count)
    }

    func refresh(accountID: String) async {
        busyAccounts.insert(accountID)
        defer { busyAccounts.remove(accountID) }
        do {
            replace(try await api.refresh(accountID: accountID))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func beginReauthorization(accountID: String) async -> LoginSession? {
        busyAccounts.insert(accountID)
        defer { busyAccounts.remove(accountID) }
        do {
            let session = try await api.startAuthorization(accountID: accountID)
            loginSessions[accountID] = session
            errorMessage = nil
            startPolling(accountID: accountID, sessionID: session.sessionID)
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createAccount(name: String) async -> AccountSnapshot? {
        guard !isCreatingAccount else { return nil }
        isCreatingAccount = true
        defer { isCreatingAccount = false }
        do {
            let account = try await api.createAccount(name: name)
            replace(account)
            errorMessage = nil
            return account
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteAccount(accountID: String) async -> Bool {
        busyAccounts.insert(accountID)
        defer { busyAccounts.remove(accountID) }
        do {
            try await api.deleteAccount(accountID: accountID)
            loginTasks[accountID]?.cancel()
            loginTasks.removeValue(forKey: accountID)
            loginSessions.removeValue(forKey: accountID)
            accounts.removeAll { $0.id == accountID }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func consumeResetCredit(accountID: String) async -> String? {
        busyAccounts.insert(accountID)
        defer { busyAccounts.remove(accountID) }
        do {
            let result = try await api.consumeResetCredit(
                accountID: accountID,
                idempotencyKey: UUID().uuidString
            )
            replace(result.account)
            errorMessage = nil
            return result.outcome
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func startPolling(accountID: String, sessionID: String) {
        loginTasks[accountID]?.cancel()
        loginTasks[accountID] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                do {
                    let session = try await self.api.authorizationStatus(sessionID: sessionID)
                    self.loginSessions[accountID] = session
                    if session.status == "succeeded" {
                        if let account = session.account { self.replace(account) }
                        return
                    }
                    if session.status == "failed" { return }
                } catch {
                    self.errorMessage = error.localizedDescription
                    return
                }
            }
        }
    }

    private func replace(_ account: AccountSnapshot) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        updatedAt = max(updatedAt, account.checkedAt)
    }

    nonisolated static func clampedPollSeconds(_ seconds: Int) -> Int {
        min(3_600, max(60, seconds))
    }
}
