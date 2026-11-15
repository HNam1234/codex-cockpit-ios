import Combine
import Foundation

enum MailboxReplacementPolicy: Sendable {
    case deleteExisting
    case keepExistingUnlinked
}

@MainActor
final class DisposableMailStore: ObservableObject {
    @Published private(set) var mailboxes: [DisposableMailbox]
    @Published private(set) var messagesByMailbox: [UUID: [DisposableMessage]]
    @Published private(set) var busyMailboxIDs: Set<UUID> = []
    @Published private(set) var isCreating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var retryAt: Date?

    var activeMailboxes: [DisposableMailbox] {
        mailboxes.filter { $0.state == .active || $0.state == .providerUnavailable }
    }

    private let provider: any DisposableMailServing
    private let vault: any DisposableMailCredentialVaultProtocol
    private let persistence: any DisposableMailPersisting
    private let reminders: any DisposableMailReminderScheduling
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let maximumCreateAttempts = 3
    private let staleInterval: TimeInterval = 60

    init(
        provider: any DisposableMailServing = MailTMClient(),
        vault: any DisposableMailCredentialVaultProtocol = DisposableMailCredentialVault(),
        persistence: any DisposableMailPersisting = DisposableMailPersistence(),
        reminders: any DisposableMailReminderScheduling = DisposableMailReminderScheduler(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.provider = provider
        self.vault = vault
        self.persistence = persistence
        self.reminders = reminders
        self.calendar = calendar
        self.now = now
        self.makeID = makeID

        let snapshot = (try? persistence.load()) ?? .empty
        mailboxes = snapshot.mailboxes
        messagesByMailbox = snapshot.messagesByMailbox
    }

    @discardableResult
    func create(
        lifetime: MailboxLifetime = .default,
        linkedAccountID: String?
    ) async -> DisposableMailbox? {
        guard !isCreating else { return nil }
        isCreating = true
        clearError()
        defer { isCreating = false }

        do {
            guard let domain = try await provider.availableDomains().first else {
                throw DisposableMailServiceError.unavailable
            }

            for attempt in 0..<maximumCreateAttempts {
                let seed = try await provider.makeAccountSeed(domain: domain.domain)
                let account: MailTMAccount
                do {
                    account = try await provider.createAccount(
                        address: seed.address,
                        password: seed.password
                    )
                } catch DisposableMailServiceError.conflict where attempt + 1 < maximumCreateAttempts {
                    continue
                }

                guard !account.isDisabled, !account.isDeleted else {
                    throw DisposableMailServiceError.missing
                }

                let credential: MailTMCredential
                do {
                    credential = try await provider.authenticate(
                        address: seed.address,
                        password: seed.password
                    )
                } catch {
                    await cleanupPartialAccount(account, seed: seed, credential: nil)
                    throw error
                }

                let createdAt = now()
                let mailbox = DisposableMailbox(
                    id: makeID(),
                    providerAccountID: account.id,
                    address: account.address,
                    createdAt: createdAt,
                    expiresAt: lifetime.expiry(from: createdAt, calendar: calendar),
                    lifetime: lifetime,
                    linkedAccountID: linkedAccountID,
                    state: .active,
                    unreadCount: 0,
                    lastSyncedAt: nil,
                    errorCategory: nil
                )

                do {
                    try vault.save(credential, mailboxID: mailbox.id)
                    let candidate = DisposableMailSnapshot(
                        mailboxes: mailboxes + [mailbox],
                        messagesByMailbox: messagesByMailbox
                    )
                    try persistence.save(candidate)
                    mailboxes = candidate.mailboxes
                    await reminders.schedule(mailbox: mailbox)
                    return mailbox
                } catch {
                    try? vault.delete(mailboxID: mailbox.id)
                    await cleanupPartialAccount(account, seed: seed, credential: credential)
                    throw error
                }
            }
            throw DisposableMailServiceError.conflict
        } catch {
            present(error)
            return nil
        }
    }

    func refresh(mailboxID: UUID, force: Bool = false) async {
        guard let index = mailboxes.firstIndex(where: { $0.id == mailboxID }),
              mailboxes[index].state == .active || mailboxes[index].state == .providerUnavailable,
              busyMailboxIDs.insert(mailboxID).inserted else { return }
        defer { busyMailboxIDs.remove(mailboxID) }

        let mailbox = mailboxes[index]
        if !force, let lastSync = mailbox.lastSyncedAt,
           now().timeIntervalSince(lastSync) < staleInterval {
            return
        }
        clearError()

        do {
            guard let credential = try vault.credential(mailboxID: mailboxID) else {
                throw DisposableMailServiceError.unauthorized
            }
            let (messages, _) = try await withRefreshedCredential(
                mailboxID: mailboxID,
                credential: credential
            ) { token in
                try await self.provider.listMessages(mailboxID: mailboxID, token: token)
            }

            messagesByMailbox[mailboxID] = messages.sorted { $0.receivedAt > $1.receivedAt }
            updateMailbox(mailboxID) { value in
                value.unreadCount = messages.lazy.filter { !$0.seen }.count
                value.lastSyncedAt = now()
                value.state = .active
                value.errorCategory = nil
            }
            persistCurrentState()
        } catch {
            applyRefreshError(error, mailboxID: mailboxID)
        }
    }

    @discardableResult
    func loadMessage(mailboxID: UUID, messageID: String) async -> DisposableMessage? {
        guard mailboxes.contains(where: { $0.id == mailboxID }),
              busyMailboxIDs.insert(mailboxID).inserted else { return nil }
        defer { busyMailboxIDs.remove(mailboxID) }
        clearError()

        do {
            guard let credential = try vault.credential(mailboxID: mailboxID) else {
                throw DisposableMailServiceError.unauthorized
            }
            var (message, activeCredential) = try await withRefreshedCredential(
                mailboxID: mailboxID,
                credential: credential
            ) { token in
                try await self.provider.message(
                    mailboxID: mailboxID,
                    messageID: messageID,
                    token: token
                )
            }
            if !message.seen {
                do {
                    try await provider.markSeen(messageID: messageID, token: activeCredential.token)
                    message.seen = true
                } catch DisposableMailServiceError.unauthorized {
                    let renewed = try await provider.authenticate(
                        address: activeCredential.address,
                        password: activeCredential.password
                    )
                    try vault.save(renewed, mailboxID: mailboxID)
                    activeCredential = renewed
                    try await provider.markSeen(messageID: messageID, token: renewed.token)
                    message.seen = true
                }
            }
            var messages = messagesByMailbox[mailboxID] ?? []
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index] = message
            } else {
                messages.insert(message, at: 0)
            }
            messagesByMailbox[mailboxID] = messages
            updateMailbox(mailboxID) { value in
                value.unreadCount = messages.lazy.filter { !$0.seen }.count
            }
            persistCurrentState()
            return message
        } catch {
            applyRefreshError(error, mailboxID: mailboxID)
            return nil
        }
    }

    func delete(mailboxID: UUID) async {
        guard let mailbox = mailboxes.first(where: { $0.id == mailboxID }),
              busyMailboxIDs.insert(mailboxID).inserted else { return }
        defer { busyMailboxIDs.remove(mailboxID) }
        clearError()

        do {
            guard let credential = try vault.credential(mailboxID: mailboxID) else {
                markPendingDeletion(mailboxID, error: .authentication)
                return
            }
            do {
                _ = try await withRefreshedCredential(
                    mailboxID: mailboxID,
                    credential: credential
                ) { token in
                    try await self.provider.deleteAccount(
                        accountID: mailbox.providerAccountID,
                        token: token
                    )
                }
            } catch DisposableMailServiceError.missing {
                // A missing provider account confirms that remote cleanup is complete.
            }
            try removeLocally(mailboxID: mailboxID)
        } catch {
            let category = category(for: error)
            markPendingDeletion(mailboxID, error: category)
            present(error)
        }
    }

    func retryPendingDeletions() async {
        let ids = mailboxes
            .filter { $0.state == .pendingDeletion || $0.state == .expired }
            .map(\.id)
        for id in ids {
            await delete(mailboxID: id)
        }
    }

    func handleForeground(validAccountIDs: Set<String>) async {
        var changed = false
        for index in mailboxes.indices {
            if let linked = mailboxes[index].linkedAccountID,
               !validAccountIDs.contains(linked) {
                mailboxes[index].linkedAccountID = nil
                changed = true
            }
            if mailboxes[index].state == .active,
               mailboxes[index].isExpired(at: now()) {
                mailboxes[index].state = .expired
                reminders.cancel(mailboxID: mailboxes[index].id)
                changed = true
            }
        }
        if changed { persistCurrentState() }

        await retryPendingDeletions()
        let refreshIDs = mailboxes.filter { $0.state == .active }.map(\.id)
        for id in refreshIDs {
            await refresh(mailboxID: id, force: false)
        }
    }

    func link(
        mailboxID: UUID,
        toAccountID accountID: String,
        replacement: MailboxReplacementPolicy?
    ) {
        clearError()
        guard let targetIndex = mailboxes.firstIndex(where: { $0.id == mailboxID }),
              mailboxes[targetIndex].state == .active || mailboxes[targetIndex].state == .providerUnavailable else {
            errorMessage = "The temporary mailbox is unavailable."
            return
        }

        let oldMailboxes = mailboxes
        if let existingIndex = mailboxes.firstIndex(where: {
            $0.id != mailboxID &&
                $0.linkedAccountID == accountID &&
                ($0.state == .active || $0.state == .providerUnavailable)
        }) {
            guard let replacement else {
                errorMessage = "Choose what to do with the mailbox already linked to this account."
                return
            }
            switch replacement {
            case .keepExistingUnlinked:
                mailboxes[existingIndex].linkedAccountID = nil
            case .deleteExisting:
                mailboxes[existingIndex].linkedAccountID = nil
                mailboxes[existingIndex].state = .pendingDeletion
                reminders.cancel(mailboxID: mailboxes[existingIndex].id)
            }
        }
        guard let currentTargetIndex = mailboxes.firstIndex(where: { $0.id == mailboxID }) else { return }
        mailboxes[currentTargetIndex].linkedAccountID = accountID
        do {
            try persistence.save(currentSnapshot())
        } catch {
            mailboxes = oldMailboxes
            present(error)
        }
    }

    func unlinkAccount(_ accountID: String) {
        let oldMailboxes = mailboxes
        var changed = false
        for index in mailboxes.indices where mailboxes[index].linkedAccountID == accountID {
            mailboxes[index].linkedAccountID = nil
            changed = true
        }
        guard changed else { return }
        do {
            try persistence.save(currentSnapshot())
            clearError()
        } catch {
            mailboxes = oldMailboxes
            present(error)
        }
    }

    func mailbox(linkedTo accountID: String) -> DisposableMailbox? {
        activeMailboxes.first { $0.linkedAccountID == accountID }
    }

    func forgetLocally(mailboxID: UUID) {
        do {
            try removeLocally(mailboxID: mailboxID)
            clearError()
        } catch {
            present(error)
        }
    }

    private func cleanupPartialAccount(
        _ account: MailTMAccount,
        seed: MailTMAccountSeed,
        credential: MailTMCredential?
    ) async {
        var cleanupCredential = credential
        if cleanupCredential == nil {
            cleanupCredential = try? await provider.authenticate(
                address: seed.address,
                password: seed.password
            )
        }
        if let cleanupCredential {
            try? await provider.deleteAccount(
                accountID: account.id,
                token: cleanupCredential.token
            )
        }
    }

    private func withRefreshedCredential<Value>(
        mailboxID: UUID,
        credential: MailTMCredential,
        operation: (String) async throws -> Value
    ) async throws -> (Value, MailTMCredential) {
        do {
            return (try await operation(credential.token), credential)
        } catch DisposableMailServiceError.unauthorized {
            let renewed = try await provider.authenticate(
                address: credential.address,
                password: credential.password
            )
            try vault.save(renewed, mailboxID: mailboxID)
            return (try await operation(renewed.token), renewed)
        }
    }

    private func applyRefreshError(_ error: Error, mailboxID: UUID) {
        let category = category(for: error)
        updateMailbox(mailboxID) { mailbox in
            mailbox.errorCategory = category
            if category == .missing || category == .authentication {
                mailbox.state = .providerUnavailable
            }
        }
        if case let DisposableMailServiceError.rateLimited(date) = error {
            retryAt = date
        }
        persistCurrentState()
        present(error)
    }

    private func markPendingDeletion(_ mailboxID: UUID, error: DisposableMailErrorCategory) {
        updateMailbox(mailboxID) { mailbox in
            mailbox.state = .pendingDeletion
            mailbox.errorCategory = error
            mailbox.linkedAccountID = nil
        }
        reminders.cancel(mailboxID: mailboxID)
        persistCurrentState()
    }

    private func removeLocally(mailboxID: UUID) throws {
        let candidateMailboxes = mailboxes.filter { $0.id != mailboxID }
        var candidateMessages = messagesByMailbox
        candidateMessages.removeValue(forKey: mailboxID)
        let candidate = DisposableMailSnapshot(
            mailboxes: candidateMailboxes,
            messagesByMailbox: candidateMessages
        )
        try persistence.save(candidate)
        do {
            try vault.delete(mailboxID: mailboxID)
        } catch {
            try? persistence.save(currentSnapshot())
            throw error
        }
        reminders.cancel(mailboxID: mailboxID)
        mailboxes = candidateMailboxes
        messagesByMailbox = candidateMessages
    }

    private func updateMailbox(_ mailboxID: UUID, mutation: (inout DisposableMailbox) -> Void) {
        guard let index = mailboxes.firstIndex(where: { $0.id == mailboxID }) else { return }
        mutation(&mailboxes[index])
    }

    private func persistCurrentState() {
        do {
            try persistence.save(currentSnapshot())
        } catch {
            present(error)
        }
    }

    private func currentSnapshot() -> DisposableMailSnapshot {
        DisposableMailSnapshot(mailboxes: mailboxes, messagesByMailbox: messagesByMailbox)
    }

    private func clearError() {
        errorMessage = nil
        retryAt = nil
    }

    private func present(_ error: Error) {
        let serviceError = error as? DisposableMailServiceError
        switch serviceError {
        case .offline:
            errorMessage = "Temporary mail is offline. Cached messages remain available."
        case .unavailable:
            errorMessage = "Temporary mail is temporarily unavailable."
        case .unauthorized:
            errorMessage = "Temporary mailbox authorization failed."
        case .missing:
            errorMessage = "The temporary mailbox no longer exists at the provider."
        case .conflict:
            errorMessage = "Could not reserve a unique temporary mailbox address."
        case .rateLimited:
            errorMessage = "Temporary mail is rate limited. Please try again later."
        case .malformedResponse:
            errorMessage = "Temporary mail returned an invalid response."
        case .rejectedHost:
            errorMessage = "Temporary mail blocked an unexpected server."
        case .entropyUnavailable:
            errorMessage = "Secure temporary mailbox creation is unavailable."
        case nil:
            errorMessage = "Temporary mail could not save its local data."
        }
    }

    private func category(for error: Error) -> DisposableMailErrorCategory {
        switch error as? DisposableMailServiceError {
        case .offline:
            .offline
        case .unauthorized:
            .authentication
        case .missing:
            .missing
        case .rateLimited:
            .rateLimited
        case .unavailable, .malformedResponse, .rejectedHost, .entropyUnavailable, .conflict, nil:
            .provider
        }
    }
}
