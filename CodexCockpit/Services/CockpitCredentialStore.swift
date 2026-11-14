import Combine
import Foundation
import Security

enum CockpitCredentialError: LocalizedError, Equatable {
    case invalidToken
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Token phải có ít nhất 32 ký tự và chỉ gồm chữ, số, dấu gạch ngang hoặc gạch dưới."
        case .keychain(let status):
            return "Không thể truy cập iOS Keychain (mã \(status))."
        }
    }
}

enum CockpitCredential {
    private static let allowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    static func validate(_ rawValue: String) throws -> String {
        let token = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 32,
              token.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw CockpitCredentialError.invalidToken
        }
        return token
    }
}

final class CockpitCredentialStore: @unchecked Sendable {
    static let shared = CockpitCredentialStore()

    private let service: String
    private let account: String

    init(
        service: String = "vn.nam.CodexCockpit",
        account: String = "cockpit-app-token"
    ) {
        self.service = service
        self.account = account
    }

    var isConfigured: Bool {
        (try? load()) != nil
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CockpitCredentialError.keychain(status) }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw CockpitCredentialError.keychain(errSecDecode)
        }
        return token
    }

    func save(_ rawValue: String) throws {
        let token = try CockpitCredential.validate(rawValue)
        let data = Data(token.utf8)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CockpitCredentialError.keychain(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CockpitCredentialError.keychain(addStatus) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CockpitCredentialError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

@MainActor
final class CockpitCredentialModel: ObservableObject {
    @Published var tokenInput = ""
    @Published private(set) var isConfigured: Bool
    @Published private(set) var errorMessage: String?
    @Published private(set) var revision = 0

    private let store: CockpitCredentialStore

    init(store: CockpitCredentialStore = .shared) {
        self.store = store
        isConfigured = store.isConfigured
    }

    @discardableResult
    func save() -> Bool {
        do {
            try store.save(tokenInput)
            tokenInput = ""
            isConfigured = true
            errorMessage = nil
            revision += 1
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func clear() -> Bool {
        do {
            try store.clear()
            tokenInput = ""
            isConfigured = false
            errorMessage = nil
            revision += 1
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
