import CryptoKit
import Foundation
import Security

struct DirectOAuthAttempt: Hashable {
    let authorizationURL: URL
    let redirectURI: URL
    let state: String
    let nonce: String
    let codeVerifier: String
    let requestedClientID: String
    let expectedSubject: String?
}

struct DirectOAuthCallback: Hashable {
    let code: String
    let issuedClientID: String?
}

struct DirectOAuthCapture: Hashable {
    let attempt: DirectOAuthAttempt
    let callback: DirectOAuthCallback
}

struct DirectOAuthRegistration: Codable, Hashable, Identifiable {
    let profileID: String
    let clientID: String
    let subject: String
    let email: String
    let name: String?
    let idToken: String
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let scopes: [String]
    let expiresAt: Int
    let earliestRefreshAt: Int?

    var id: String { profileID }
}

struct VerifiedOAuthIdentity: Equatable {
    let subject: String
    let email: String
    let name: String?
}

enum DirectOAuthCallbackInspection: Equatable {
    case notCallback
    case captured(DirectOAuthCallback)
    case rejected(DirectOAuthError)
}

enum DirectOAuthError: Error, Equatable, LocalizedError {
    case invalidHostID
    case invalidEntropy
    case invalidCallback
    case callbackMismatch
    case stateMismatch
    case clientMismatch
    case authorizationDenied(String?)
    case tokenExchangeFailed(Int)
    case invalidTokenResponse
    case invalidIDToken
    case unverifiedEmail
    case identityMismatch
    case keychainFailure(Int32)

    var localizationKey: String {
        switch self {
        case .invalidHostID: "oauth.direct.error.invalidHostID"
        case .invalidEntropy: "oauth.direct.error.invalidEntropy"
        case .invalidCallback: "oauth.direct.error.invalidCallback"
        case .callbackMismatch: "oauth.direct.error.callbackMismatch"
        case .stateMismatch: "oauth.direct.error.stateMismatch"
        case .clientMismatch: "oauth.direct.error.clientMismatch"
        case .authorizationDenied: "oauth.direct.error.authorizationDenied"
        case .tokenExchangeFailed: "oauth.direct.error.tokenExchangeFailed"
        case .invalidTokenResponse: "oauth.direct.error.invalidTokenResponse"
        case .invalidIDToken: "oauth.direct.error.invalidIDToken"
        case .unverifiedEmail: "oauth.direct.error.unverifiedEmail"
        case .identityMismatch: "oauth.direct.error.identityMismatch"
        case .keychainFailure: "oauth.direct.error.keychainFailure"
        }
    }

    var errorDescription: String? { L10n.text(localizationKey) }
}

enum DirectOAuthFlow {
    static let dynamicClientID = "dynamic_agent_client"
    static let redirectURI = URL(string: "http://127.0.0.1:1455/auth/callback")!
    static let authorizationEndpoint = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let jwksEndpoint = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
    static let resource = "https://api.openai.com/v1"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

    static func prepare(hostID: String, registration: DirectOAuthRegistration?) throws -> DirectOAuthAttempt {
        try makeAttempt(
            hostID: hostID,
            registration: registration,
            state: randomBase64URL(byteCount: 32),
            nonce: randomBase64URL(byteCount: 32),
            codeVerifier: randomBase64URL(byteCount: 64)
        )
    }

    static func makeAttempt(
        hostID: String,
        registration: DirectOAuthRegistration?,
        state: String,
        nonce: String,
        codeVerifier: String
    ) throws -> DirectOAuthAttempt {
        guard hostID.hasPrefix("urn:uuid:"),
              UUID(uuidString: String(hostID.dropFirst("urn:uuid:".count))) != nil else {
            throw DirectOAuthError.invalidHostID
        }
        guard !state.isEmpty, !nonce.isEmpty, (43...128).contains(codeVerifier.count) else {
            throw DirectOAuthError.invalidEntropy
        }

        let clientID = registration?.clientID ?? dynamicClientID
        let challenge = Data(SHA256.hash(data: Data(codeVerifier.utf8))).base64URLEncodedString()
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if let registration {
            queryItems.append(URLQueryItem(name: "id_token_hint", value: registration.idToken))
            queryItems.append(URLQueryItem(name: "login_hint", value: registration.email))
        } else {
            queryItems.append(URLQueryItem(name: "agent_name_hint", value: "Codex Cockpit"))
        }

        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        guard let authorizationURL = components.url else { throw DirectOAuthError.invalidCallback }
        return DirectOAuthAttempt(
            authorizationURL: authorizationURL,
            redirectURI: redirectURI,
            state: state,
            nonce: nonce,
            codeVerifier: codeVerifier,
            requestedClientID: clientID,
            expectedSubject: registration?.subject
        )
    }

    static func inspectCallback(_ url: URL, for attempt: DirectOAuthAttempt) -> DirectOAuthCallbackInspection {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let resemblesCallback = url.path == attempt.redirectURI.path
            || url.host?.lowercased() == "127.0.0.1"
            || url.host?.lowercased() == "localhost"
        guard resemblesCallback else { return .notCallback }
        guard url.scheme?.lowercased() == "http",
              url.host?.lowercased() == attempt.redirectURI.host,
              url.port == attempt.redirectURI.port,
              url.path == attempt.redirectURI.path else {
            return .rejected(.callbackMismatch)
        }

        let values = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        if let authorizationError = values["error"], !authorizationError.isEmpty {
            return .rejected(.authorizationDenied(values["error_description"] ?? authorizationError))
        }
        guard let returnedState = values["state"],
              constantTimeEqual(returnedState, attempt.state) else {
            return .rejected(.stateMismatch)
        }
        guard let code = values["code"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else {
            return .rejected(.invalidCallback)
        }

        let issuedClientID = values["client_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if attempt.requestedClientID == dynamicClientID {
            guard let issuedClientID, !issuedClientID.isEmpty else {
                return .rejected(.clientMismatch)
            }
        } else if let issuedClientID,
                  !issuedClientID.isEmpty,
                  !constantTimeEqual(issuedClientID, attempt.requestedClientID) {
            return .rejected(.clientMismatch)
        }
        return .captured(DirectOAuthCallback(
            code: code,
            issuedClientID: issuedClientID?.isEmpty == false ? issuedClientID : nil
        ))
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }

    private static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw DirectOAuthError.invalidEntropy
        }
        return Data(bytes).base64URLEncodedString()
    }
}

actor DirectOAuthClient {
    private let session: URLSession
    private let verifier: OpenAIIDTokenVerifier

    init(session: URLSession = .shared, verifier: OpenAIIDTokenVerifier? = nil) {
        self.session = session
        self.verifier = verifier ?? OpenAIIDTokenVerifier(session: session)
    }

    func exchange(
        capture: DirectOAuthCapture,
        profileID: String,
        previous: DirectOAuthRegistration?
    ) async throws -> DirectOAuthRegistration {
        let clientID = capture.callback.issuedClientID ?? capture.attempt.requestedClientID
        guard clientID != DirectOAuthFlow.dynamicClientID else {
            throw DirectOAuthError.clientMismatch
        }

        var request = URLRequest(url: DirectOAuthFlow.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: capture.callback.code),
            URLQueryItem(name: "redirect_uri", value: capture.attempt.redirectURI.absoluteString),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: capture.attempt.codeVerifier),
            URLQueryItem(name: "resource", value: DirectOAuthFlow.resource)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DirectOAuthError.invalidTokenResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw DirectOAuthError.tokenExchangeFailed(http.statusCode)
        }
        let token: TokenResponse
        do {
            token = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw DirectOAuthError.invalidTokenResponse
        }
        let identity = try await verifier.verify(
            idToken: token.idToken,
            clientID: clientID,
            nonce: capture.attempt.nonce
        )
        if let expectedSubject = capture.attempt.expectedSubject,
           !DirectOAuthFlow.constantTimeEqual(expectedSubject, identity.subject) {
            throw DirectOAuthError.identityMismatch
        }

        return DirectOAuthRegistration(
            profileID: profileID,
            clientID: clientID,
            subject: identity.subject,
            email: identity.email,
            name: identity.name,
            idToken: token.idToken,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? previous?.refreshToken,
            tokenType: token.tokenType,
            scopes: token.scope?.split(separator: " ").map(String.init) ?? [],
            expiresAt: Int(Date().timeIntervalSince1970) + max(0, token.expiresIn),
            earliestRefreshAt: token.earliestRefreshAt
        )
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String
    let tokenType: String
    let expiresIn: Int
    let scope: String?
    let earliestRefreshAt: Int?

    enum CodingKeys: String, CodingKey {
        case scope
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case earliestRefreshAt = "earliest_refresh_at"
    }
}

actor OpenAIIDTokenVerifier {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func verify(idToken: String, clientID: String, nonce: String) async throws -> VerifiedOAuthIdentity {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = Data(base64URLEncoded: String(parts[0])),
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let signature = Data(base64URLEncoded: String(parts[2])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              header["alg"] as? String == "RS256",
              let keyID = header["kid"] as? String,
              !keyID.isEmpty else {
            throw DirectOAuthError.invalidIDToken
        }

        let (jwksData, response) = try await session.data(from: DirectOAuthFlow.jwksEndpoint)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let keys = try? JSONDecoder().decode(JWKSet.self, from: jwksData).keys,
              let jwk = keys.first(where: { $0.kid == keyID && $0.kty == "RSA" }),
              let key = Self.makeRSAKey(jwk) else {
            throw DirectOAuthError.invalidIDToken
        }

        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        var verificationError: Unmanaged<CFError>?
        guard SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData,
            signature as CFData,
            &verificationError
        ) else {
            throw DirectOAuthError.invalidIDToken
        }
        return try Self.validateClaims(claims, clientID: clientID, nonce: nonce, now: .now)
    }

    nonisolated static func validateClaims(
        _ claims: [String: Any],
        clientID: String,
        nonce: String,
        now: Date
    ) throws -> VerifiedOAuthIdentity {
        guard claims["iss"] as? String == "https://auth.openai.com",
              audience(claims["aud"]).contains(clientID),
              let expiration = numericDate(claims["exp"]),
              expiration > now.timeIntervalSince1970,
              let issuedAt = numericDate(claims["iat"]),
              issuedAt <= now.timeIntervalSince1970 + 300,
              let returnedNonce = claims["nonce"] as? String,
              DirectOAuthFlow.constantTimeEqual(returnedNonce, nonce),
              let subject = nonEmpty(claims["sub"] as? String) else {
            throw DirectOAuthError.invalidIDToken
        }
        guard claims["email_verified"] as? Bool == true,
              let email = nonEmpty(claims["email"] as? String) else {
            throw DirectOAuthError.unverifiedEmail
        }
        return VerifiedOAuthIdentity(
            subject: subject,
            email: email.lowercased(),
            name: nonEmpty(claims["name"] as? String)
        )
    }

    private nonisolated static func audience(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        return value as? [String] ?? []
    }

    private nonisolated static func numericDate(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func makeRSAKey(_ jwk: JWK) -> SecKey? {
        guard let modulus = Data(base64URLEncoded: jwk.n),
              let exponent = Data(base64URLEncoded: jwk.e) else { return nil }
        let body = asn1Integer(modulus) + asn1Integer(exponent)
        let der = Data([0x30]) + asn1Length(body.count) + body
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: modulus.count * 8
        ]
        return SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil)
    }

    private nonisolated static func asn1Integer(_ value: Data) -> Data {
        var bytes = Array(value.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = [0] }
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return Data([0x02]) + asn1Length(bytes.count) + Data(bytes)
    }

    private nonisolated static func asn1Length(_ length: Int) -> Data {
        if length < 128 { return Data([UInt8(length)]) }
        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }
}

private struct JWKSet: Decodable {
    let keys: [JWK]
}

private struct JWK: Decodable {
    let kty: String
    let kid: String
    let n: String
    let e: String
}

struct DirectOAuthCredentialVault {
    private let service = "vn.nam.CodexCockpit.direct-oauth"

    func load(profileID: String) throws -> DirectOAuthRegistration? {
        var query = baseQuery(profileID: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DirectOAuthError.keychainFailure(status)
        }
        do {
            return try JSONDecoder().decode(DirectOAuthRegistration.self, from: data)
        } catch {
            throw DirectOAuthError.invalidTokenResponse
        }
    }

    func save(_ registration: DirectOAuthRegistration) throws {
        let data = try JSONEncoder().encode(registration)
        let query = baseQuery(profileID: registration.profileID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw DirectOAuthError.keychainFailure(insertStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw DirectOAuthError.keychainFailure(updateStatus)
        }
    }

    func delete(profileID: String) throws {
        let status = SecItemDelete(baseQuery(profileID: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DirectOAuthError.keychainFailure(status)
        }
    }

    private func baseQuery(profileID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID
        ]
    }
}

@MainActor
final class DirectOAuthStore: ObservableObject {
    @Published private(set) var registrations: [String: DirectOAuthRegistration] = [:]

    private let defaults: UserDefaults
    private let vault: DirectOAuthCredentialVault
    private let client: DirectOAuthClient
    private let hostIDKey = "CodexCockpit.directOAuthHostID.v1"

    init(
        defaults: UserDefaults = .standard,
        vault: DirectOAuthCredentialVault = DirectOAuthCredentialVault(),
        client: DirectOAuthClient = DirectOAuthClient()
    ) {
        self.defaults = defaults
        self.vault = vault
        self.client = client
    }

    func registration(for profileID: String) -> DirectOAuthRegistration? {
        if let cached = registrations[profileID] { return cached }
        guard let loaded = try? vault.load(profileID: profileID) else { return nil }
        registrations[profileID] = loaded
        return loaded
    }

    func restore(profileIDs: [String]) {
        var restored = registrations
        for profileID in profileIDs where restored[profileID] == nil {
            if let registration = try? vault.load(profileID: profileID) {
                restored[profileID] = registration
            }
        }
        if restored != registrations {
            registrations = restored
        }
    }

    func hasRegistration(for profileID: String) -> Bool {
        registrations[profileID] != nil
    }

    func prepare(profileID: String) throws -> DirectOAuthAttempt {
        try DirectOAuthFlow.prepare(hostID: hostID, registration: registration(for: profileID))
    }

    func complete(capture: DirectOAuthCapture, profileID: String) async throws -> DirectOAuthRegistration {
        let registration = try await client.exchange(
            capture: capture,
            profileID: profileID,
            previous: registration(for: profileID)
        )
        try vault.save(registration)
        registrations[profileID] = registration
        return registration
    }

    func clear(profileID: String) throws {
        try vault.delete(profileID: profileID)
        registrations.removeValue(forKey: profileID)
    }

    private var hostID: String {
        if let existing = defaults.string(forKey: hostIDKey),
           existing.hasPrefix("urn:uuid:") {
            return existing
        }
        let value = "urn:uuid:\(UUID().uuidString.lowercased())"
        defaults.set(value, forKey: hostIDKey)
        return value
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        var encoded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded.append(String(repeating: "=", count: (4 - encoded.count % 4) % 4))
        self.init(base64Encoded: encoded)
    }
}
