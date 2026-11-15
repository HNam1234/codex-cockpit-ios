import Foundation
import Security

struct MailTMAccountSeed: Equatable, Sendable {
    let address: String
    let password: String
}

struct MailTMCredential: Equatable, Sendable {
    let providerAccountID: String
    let address: String
    let password: String
    let token: String
}

struct MailTMAccount: Codable, Equatable, Sendable {
    let id: String
    let address: String
    let isDisabled: Bool
    let isDeleted: Bool
}

struct MailTMDomain: Codable, Equatable, Sendable {
    let id: String
    let domain: String
    let isActive: Bool
    let isPrivate: Bool
}

struct MailTMPage<Element: Decodable & Sendable>: Decodable, Sendable {
    let members: [Element]
    let totalItems: Int

    enum CodingKeys: String, CodingKey {
        case members = "hydra:member"
        case totalItems = "hydra:totalItems"
    }
}

enum DisposableMailServiceError: Error, Equatable, LocalizedError, Sendable {
    case offline
    case unavailable
    case unauthorized
    case missing
    case conflict
    case rateLimited(retryAt: Date)
    case malformedResponse
    case rejectedHost
    case entropyUnavailable

    var errorDescription: String? {
        switch self {
        case .offline: "Disposable mail is offline."
        case .unavailable: "Disposable mail is temporarily unavailable."
        case .unauthorized: "Disposable mailbox authorization failed."
        case .missing: "Disposable mailbox no longer exists."
        case .conflict: "Disposable mailbox address is already in use."
        case .rateLimited: "Disposable mail is rate limited."
        case .malformedResponse: "Disposable mail returned an invalid response."
        case .rejectedHost: "Disposable mail rejected an unexpected host."
        case .entropyUnavailable: "Secure random generation failed."
        }
    }
}

protocol DisposableMailServing: Sendable {
    func availableDomains() async throws -> [MailTMDomain]
    func makeAccountSeed(domain: String) async throws -> MailTMAccountSeed
    func createAccount(address: String, password: String) async throws -> MailTMAccount
    func authenticate(address: String, password: String) async throws -> MailTMCredential
    func listMessages(mailboxID: UUID, token: String) async throws -> [DisposableMessage]
    func message(mailboxID: UUID, messageID: String, token: String) async throws -> DisposableMessage
    func markSeen(messageID: String, token: String) async throws
    func deleteAccount(accountID: String, token: String) async throws
}

final class MailTMRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func isAllowed(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let hasCredentials = components.user != nil || components.password != nil
        return components.scheme?.lowercased() == "https"
            && components.host?.lowercased() == "api.mail.tm"
            && !hasCredentials
            && (components.port == nil || components.port == 443)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(Self.isAllowed) == true ? request : nil)
    }
}

actor MailTMClient: DisposableMailServing {
    private let session: URLSession
    private let baseURL: URL
    private let redirectGuard = MailTMRedirectGuard()
    private let minimumRequestInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let jitter: @Sendable (TimeInterval) -> TimeInterval
    private let accountSeed: @Sendable (String) throws -> MailTMAccountSeed
    private var nextRequestAt: Date?

    init(
        session: URLSession? = nil,
        baseURL: URL = URL(string: "https://api.mail.tm")!,
        minimumRequestInterval: TimeInterval = 0.25,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        jitter: @escaping @Sendable (TimeInterval) -> TimeInterval = { base in
            Double.random(in: 0...(base * 0.2))
        },
        accountSeed: @escaping @Sendable (String) throws -> MailTMAccountSeed = MailTMClient.secureAccountSeed
    ) {
        self.session = session ?? Self.ephemeralSession()
        self.baseURL = baseURL
        self.minimumRequestInterval = max(0, minimumRequestInterval)
        self.now = now
        self.sleep = sleep
        self.jitter = jitter
        self.accountSeed = accountSeed
    }

    func availableDomains() async throws -> [MailTMDomain] {
        let data = try await perform(
            path: ["domains"],
            queryItems: [URLQueryItem(name: "page", value: "1")],
            idempotent: true,
            expectedStatus: [200]
        )
        let page: MailTMPage<MailTMDomain> = try decode(data)
        return page.members.filter { $0.isActive && !$0.isPrivate && !$0.domain.isEmpty }
    }

    func makeAccountSeed(domain: String) async throws -> MailTMAccountSeed {
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedDomain.isEmpty,
              normalizedDomain.range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil else {
            throw DisposableMailServiceError.malformedResponse
        }
        let seed = try accountSeed(normalizedDomain)
        guard seed.address.hasSuffix("@\(normalizedDomain)"), !seed.password.isEmpty else {
            throw DisposableMailServiceError.malformedResponse
        }
        return seed
    }

    func createAccount(address: String, password: String) async throws -> MailTMAccount {
        let body = try jsonBody(["address": address, "password": password])
        let data = try await perform(
            path: ["accounts"],
            method: "POST",
            body: body,
            idempotent: false,
            expectedStatus: [200, 201]
        )
        return try decode(data)
    }

    func authenticate(address: String, password: String) async throws -> MailTMCredential {
        let body = try jsonBody(["address": address, "password": password])
        let data = try await perform(
            path: ["token"],
            method: "POST",
            body: body,
            idempotent: false,
            expectedStatus: [200]
        )
        let response: MailTMToken = try decode(data)
        guard !response.id.isEmpty, !response.token.isEmpty else {
            throw DisposableMailServiceError.malformedResponse
        }
        return MailTMCredential(
            providerAccountID: response.id,
            address: address,
            password: password,
            token: response.token
        )
    }

    func listMessages(mailboxID: UUID, token: String) async throws -> [DisposableMessage] {
        let data = try await perform(
            path: ["messages"],
            queryItems: [URLQueryItem(name: "page", value: "1")],
            token: token,
            idempotent: true,
            expectedStatus: [200]
        )
        let page: MailTMPage<MailTMMessageSummary> = try decode(data)
        return page.members.map { $0.disposableMessage(mailboxID: mailboxID) }
    }

    func message(mailboxID: UUID, messageID: String, token: String) async throws -> DisposableMessage {
        let data = try await perform(
            path: ["messages", messageID],
            token: token,
            idempotent: true,
            expectedStatus: [200]
        )
        let detail: MailTMMessageDetail = try decode(data)
        return detail.disposableMessage(mailboxID: mailboxID)
    }

    func markSeen(messageID: String, token: String) async throws {
        _ = try await perform(
            path: ["messages", messageID],
            method: "PATCH",
            token: token,
            body: try jsonBody(["seen": true]),
            idempotent: false,
            expectedStatus: [200, 204]
        )
    }

    func deleteAccount(accountID: String, token: String) async throws {
        _ = try await perform(
            path: ["accounts", accountID],
            method: "DELETE",
            token: token,
            idempotent: false,
            expectedStatus: [200, 204]
        )
    }

    private func perform(
        path: [String],
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        token: String? = nil,
        body: Data? = nil,
        idempotent: Bool,
        expectedStatus: Set<Int>
    ) async throws -> Data {
        let url = try makeURL(path: path, queryItems: queryItems)
        var retry = 0
        while true {
            try await waitForRateLimit()
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

            let data: Data
            let response: HTTPURLResponse
            do {
                let result = try await session.data(for: request, delegate: redirectGuard)
                guard let http = result.1 as? HTTPURLResponse else {
                    throw DisposableMailServiceError.malformedResponse
                }
                data = result.0
                response = http
            } catch let error as DisposableMailServiceError {
                throw error
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                    throw DisposableMailServiceError.offline
                default:
                    throw DisposableMailServiceError.unavailable
                }
            } catch {
                throw DisposableMailServiceError.unavailable
            }

            if expectedStatus.contains(response.statusCode) { return data }
            if response.statusCode == 401 { throw DisposableMailServiceError.unauthorized }
            if response.statusCode == 404 { throw DisposableMailServiceError.missing }
            if response.statusCode == 409 || response.statusCode == 422 {
                throw DisposableMailServiceError.conflict
            }

            if response.statusCode == 429 {
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                let delay = max(0, retryAfter ?? backoff(for: retry))
                let retryAt = now().addingTimeInterval(delay)
                guard idempotent, retry < 3 else {
                    throw DisposableMailServiceError.rateLimited(retryAt: retryAt)
                }
                retry += 1
                try await sleep(delay)
                continue
            }

            if (500...599).contains(response.statusCode), idempotent, retry < 3 {
                let delay = backoff(for: retry)
                retry += 1
                try await sleep(delay)
                continue
            }
            throw DisposableMailServiceError.unavailable
        }
    }

    private func waitForRateLimit() async throws {
        guard minimumRequestInterval > 0 else { return }
        let current = now()
        let scheduled = max(current, nextRequestAt ?? current)
        nextRequestAt = scheduled.addingTimeInterval(minimumRequestInterval)
        let delay = scheduled.timeIntervalSince(current)
        if delay > 0 { try await sleep(delay) }
    }

    private func backoff(for retry: Int) -> TimeInterval {
        let base = min(4, pow(2, Double(retry)))
        return base + max(0, jitter(base))
    }

    private func makeURL(path: [String], queryItems: [URLQueryItem]) throws -> URL {
        guard MailTMRedirectGuard.isAllowed(baseURL),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DisposableMailServiceError.rejectedHost
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = try path.map { component -> String in
            guard !component.isEmpty,
                  let value = component.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw DisposableMailServiceError.malformedResponse
            }
            return value
        }
        components.percentEncodedPath = "/" + encoded.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url, MailTMRedirectGuard.isAllowed(url) else {
            throw DisposableMailServiceError.rejectedHost
        }
        return url
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try Self.decoder().decode(Value.self, from: data)
        } catch {
            throw DisposableMailServiceError.malformedResponse
        }
    }

    private func jsonBody(_ object: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw DisposableMailServiceError.malformedResponse
        }
    }

    private static func ephemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: value) ?? standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date"
                )
            }
            return date
        }
        return decoder
    }

    static func secureAccountSeed(domain: String) throws -> MailTMAccountSeed {
        let local = try secureRandom(byteCount: 10).map { String(format: "%02x", $0) }.joined()
        let generatedSecret = try secureRandom(byteCount: 32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return MailTMAccountSeed(address: "cc-\(local)@\(domain)", password: generatedSecret)
    }

    private static func secureRandom(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw DisposableMailServiceError.entropyUnavailable
        }
        return Data(bytes)
    }
}

private struct MailTMToken: Decodable {
    let id: String
    let token: String
}

private struct MailTMAddress: Decodable, Sendable {
    let address: String
    let name: String?
}

private struct MailTMMessageSummary: Decodable, Sendable {
    let id: String
    let from: MailTMAddress
    let subject: String
    let intro: String
    let seen: Bool
    let createdAt: Date

    func disposableMessage(mailboxID: UUID) -> DisposableMessage {
        DisposableMessage(
            id: id,
            mailboxID: mailboxID,
            senderName: from.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            senderAddress: from.address,
            subject: subject,
            intro: intro,
            text: "",
            receivedAt: createdAt,
            seen: seen,
            attachments: []
        )
    }
}

private struct MailTMMessageDetail: Decodable, Sendable {
    let id: String
    let from: MailTMAddress
    let subject: String
    let intro: String
    let seen: Bool
    let text: String?
    let html: MailTMHTML?
    let attachments: [MailTMAttachment]?
    let createdAt: Date

    func disposableMessage(mailboxID: UUID) -> DisposableMessage {
        DisposableMessage(
            id: id,
            mailboxID: mailboxID,
            senderName: from.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            senderAddress: from.address,
            subject: subject,
            intro: intro,
            text: MailTextSanitizer.plainText(text: text, html: html?.values ?? []),
            receivedAt: createdAt,
            seen: seen,
            attachments: (attachments ?? []).map {
                DisposableAttachment(id: $0.id, fileName: $0.filename, mediaType: $0.contentType, size: $0.size)
            }
        )
    }
}

private struct MailTMAttachment: Decodable, Sendable {
    let id: String
    let filename: String
    let contentType: String
    let size: Int
}

private struct MailTMHTML: Decodable, Sendable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            values = array
        } else if let value = try? container.decode(String.self) {
            values = [value]
        } else {
            values = []
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
