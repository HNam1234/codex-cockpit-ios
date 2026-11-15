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
    private let defaults: UserDefaults
    private let localAccountsKey = "CodexCockpit.localOAuthAccounts.v1"
    private var remoteAccounts: [AccountSnapshot] = []
    private var localAccounts: [LocalOAuthAccountRecord]
    private var loginTasks: [String: Task<Void, Never>] = [:]

    init(
        api: any CockpitAPIClient = CockpitAPI.shared,
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.defaults = defaults
        if let data = defaults.data(forKey: localAccountsKey),
           let decoded = try? JSONDecoder().decode([LocalOAuthAccountRecord].self, from: data) {
            localAccounts = decoded
        } else {
            localAccounts = []
        }
        rebuildAccounts()
    }

    func account(id: String) -> AccountSnapshot? {
        accounts.first(where: { $0.id == id })
    }

    func needsDirectOAuthRecovery(accountID: String) -> Bool {
        guard !Self.isLocalAccountID(accountID),
              let account = remoteAccounts.first(where: { $0.id == accountID }) else {
            return false
        }
        return !account.ok
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.status()
            remoteAccounts = response.accounts
            rebuildAccounts()
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
        remoteAccounts = []
        rebuildAccounts()
        capabilities = nil
        tiboReset = nil
        updatedAt = 0
        loginSessions = [:]
        busyAccounts = []
        errorMessage = nil
    }

    func refreshAll() async {
        guard !isLoading else { return }
        let accountIDs = remoteAccounts.map(\.id)
        guard !accountIDs.isEmpty else {
            errorMessage = nil
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
        guard !Self.isLocalAccountID(accountID) else { return }
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

    @discardableResult
    func createLocalAccount() -> AccountSnapshot {
        let record = LocalOAuthAccountRecord(
            id: "local:\(UUID().uuidString.lowercased())",
            email: nil,
            connected: false,
            createdAt: Int(Date().timeIntervalSince1970)
        )
        localAccounts.append(record)
        saveLocalAccounts()
        rebuildAccounts()
        return localSnapshot(record)
    }

    func completeLocalOAuth(accountID: String, email: String) {
        guard let index = localAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        localAccounts[index].email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        localAccounts[index].connected = true
        saveLocalAccounts()
        rebuildAccounts()
    }

    @discardableResult
    func importDirectOAuth(
        accountID: String,
        registration: DirectOAuthRegistration
    ) async -> AccountSnapshot? {
        guard !Self.isLocalAccountID(accountID),
              remoteAccounts.contains(where: { $0.id == accountID }) else {
            errorMessage = L10n.text("oauth.direct.error.remoteAccountRequired")
            return nil
        }
        busyAccounts.insert(accountID)
        defer { busyAccounts.remove(accountID) }
        do {
            let account = try await api.importDirectOAuth(
                accountID: accountID,
                registration: registration
            )
            guard account.id == accountID else { throw CockpitAPIError.invalidResponse }
            replace(account)
            errorMessage = nil
            return account
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func disconnectLocalOAuth(accountID: String) {
        guard let index = localAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        localAccounts[index].connected = false
        saveLocalAccounts()
        rebuildAccounts()
    }

    func deleteAccount(accountID: String) async -> Bool {
        busyAccounts.insert(accountID)
        defer { busyAccounts.remove(accountID) }
        if Self.isLocalAccountID(accountID) {
            localAccounts.removeAll { $0.id == accountID }
            saveLocalAccounts()
            rebuildAccounts()
            errorMessage = nil
            return true
        }
        do {
            try await api.deleteAccount(accountID: accountID)
            loginTasks[accountID]?.cancel()
            loginTasks.removeValue(forKey: accountID)
            loginSessions.removeValue(forKey: accountID)
            remoteAccounts.removeAll { $0.id == accountID }
            rebuildAccounts()
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
        if let index = remoteAccounts.firstIndex(where: { $0.id == account.id }) {
            remoteAccounts[index] = account
        } else {
            remoteAccounts.append(account)
        }
        rebuildAccounts()
        updatedAt = max(updatedAt, account.checkedAt)
    }

    private func rebuildAccounts() {
        accounts = remoteAccounts + localAccounts.map(localSnapshot)
    }

    private func localSnapshot(_ record: LocalOAuthAccountRecord) -> AccountSnapshot {
        AccountSnapshot(
            id: record.id,
            name: record.email ?? L10n.text("oauth.direct.pending_account"),
            displayName: record.email,
            email: record.email,
            plan: "DIRECT",
            subscriptionExpiresAt: nil,
            ok: record.connected,
            error: nil,
            windows: [],
            resetCredits: 0,
            checkedAt: record.createdAt
        )
    }

    private func saveLocalAccounts() {
        if let data = try? JSONEncoder().encode(localAccounts) {
            defaults.set(data, forKey: localAccountsKey)
        }
    }

    nonisolated static func isLocalAccountID(_ accountID: String) -> Bool {
        accountID.hasPrefix("local:")
    }

    nonisolated static func clampedPollSeconds(_ seconds: Int) -> Int {
        min(3_600, max(60, seconds))
    }
}

private struct LocalOAuthAccountRecord: Codable {
    let id: String
    var email: String?
    var connected: Bool
    let createdAt: Int
}
