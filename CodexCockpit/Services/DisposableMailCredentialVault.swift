import Foundation
import Security

enum DisposableMailKeychainAccessibility: Equatable, Sendable {
    case whenUnlockedThisDeviceOnly
}

enum DisposableMailCredentialVaultError: Error, Equatable, LocalizedError, Sendable {
    case keychainFailure(OSStatus)
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .keychainFailure:
            "Disposable mailbox credentials could not be accessed."
        case .invalidCredential:
            "Disposable mailbox credentials are invalid."
        }
    }
}

protocol DisposableMailCredentialVaultProtocol: Sendable {
    func save(_ credential: MailTMCredential, mailboxID: UUID) throws
    func credential(mailboxID: UUID) throws -> MailTMCredential?
    func delete(mailboxID: UUID) throws
}

protocol DisposableMailKeychainAccessing: Sendable {
    func data(service: String, account: String) throws -> Data?
    func upsert(
        _ data: Data,
        service: String,
        account: String,
        accessibility: DisposableMailKeychainAccessibility
    ) throws
    func delete(service: String, account: String) throws
}

struct DisposableMailCredentialVault: DisposableMailCredentialVaultProtocol, Sendable {
    private static let service = "vn.nam.CodexCockpit.disposable-mail"
    private let keychain: any DisposableMailKeychainAccessing

    init(keychain: any DisposableMailKeychainAccessing = SystemDisposableMailKeychain()) {
        self.keychain = keychain
    }

    func save(_ credential: MailTMCredential, mailboxID: UUID) throws {
        let payload = CredentialPayload(credential)
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            throw DisposableMailCredentialVaultError.invalidCredential
        }
        try keychain.upsert(
            data,
            service: Self.service,
            account: account(for: mailboxID),
            accessibility: .whenUnlockedThisDeviceOnly
        )
    }

    func credential(mailboxID: UUID) throws -> MailTMCredential? {
        guard let data = try keychain.data(
            service: Self.service,
            account: account(for: mailboxID)
        ) else { return nil }

        do {
            return try JSONDecoder().decode(CredentialPayload.self, from: data).credential
        } catch {
            throw DisposableMailCredentialVaultError.invalidCredential
        }
    }

    func delete(mailboxID: UUID) throws {
        try keychain.delete(service: Self.service, account: account(for: mailboxID))
    }

    private func account(for mailboxID: UUID) -> String {
        mailboxID.uuidString.lowercased()
    }
}

private struct CredentialPayload: Codable {
    let providerAccountID: String
    let address: String
    let password: String
    let token: String

    init(_ credential: MailTMCredential) {
        providerAccountID = credential.providerAccountID
        address = credential.address
        password
            = credential.password
        token = credential.token
    }

    var credential: MailTMCredential {
        MailTMCredential(
            providerAccountID: providerAccountID,
            address: address,
            password: password,
            token: token
        )
    }
}

struct SystemDisposableMailKeychain: DisposableMailKeychainAccessing {
    func data(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DisposableMailCredentialVaultError.keychainFailure(status)
        }
        return data
    }

    func upsert(
        _ data: Data,
        service: String,
        account: String,
        accessibility: DisposableMailKeychainAccessibility
    ) throws {
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: securityAccessibility(accessibility)
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw DisposableMailCredentialVaultError.keychainFailure(insertStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw DisposableMailCredentialVaultError.keychainFailure(updateStatus)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DisposableMailCredentialVaultError.keychainFailure(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func securityAccessibility(_ accessibility: DisposableMailKeychainAccessibility) -> CFString {
        switch accessibility {
        case .whenUnlockedThisDeviceOnly:
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }
}
