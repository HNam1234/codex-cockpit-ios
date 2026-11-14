import Foundation

enum CockpitAPIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return L10n.text("error.invalid_response")
        case .server(let message): return message
        }
    }
}

struct ResetCreditResult {
    let outcome: String
    let account: AccountSnapshot
}

protocol CockpitAPIClient: Sendable {
    func status() async throws -> NativeStatusResponse
    func refresh(accountID: String) async throws -> AccountSnapshot
    func startAuthorization(accountID: String) async throws -> LoginSession
    func authorizationStatus(sessionID: String) async throws -> LoginSession
    func consumeResetCredit(accountID: String, idempotencyKey: String) async throws -> ResetCreditResult
    func createAccount(name: String) async throws -> AccountSnapshot
    func deleteAccount(accountID: String) async throws
}

actor CockpitAPI: CockpitAPIClient {
    static let shared = CockpitAPI()

    func status() async throws -> NativeStatusResponse {
        try await post("app-status", values: [:], as: NativeStatusResponse.self)
    }

    func refresh(accountID: String) async throws -> AccountSnapshot {
        let envelope = try await post(
            "app-refresh",
            values: ["account_id": accountID],
            as: AccountEnvelope.self
        )
        return envelope.account
    }

    func startAuthorization(accountID: String) async throws -> LoginSession {
        let envelope = try await post(
            "app-auth/start",
            values: ["account_id": accountID],
            as: LoginEnvelope.self
        )
        return envelope.login
    }

    func authorizationStatus(sessionID: String) async throws -> LoginSession {
        let envelope = try await post(
            "app-auth/status",
            values: ["session_id": sessionID],
            as: LoginEnvelope.self
        )
        return envelope.login
    }

    func consumeResetCredit(accountID: String, idempotencyKey: String) async throws -> ResetCreditResult {
        let envelope = try await post(
            "app-reset-credit",
            values: ["account_id": accountID, "idempotency_key": idempotencyKey],
            as: ResetEnvelope.self
        )
        return ResetCreditResult(outcome: envelope.outcome, account: envelope.account)
    }

    func createAccount(name: String) async throws -> AccountSnapshot {
        let envelope = try await post(
            "app-account/create",
            values: ["name": name],
            as: AccountEnvelope.self
        )
        return envelope.account
    }

    func deleteAccount(accountID: String) async throws {
        _ = try await post(
            "app-account/delete",
            values: ["account_id": accountID],
            as: DeleteAccountEnvelope.self
        )
    }

    private func post<T: Decodable>(
        _ path: String,
        values: [String: String],
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: AppURLs.endpoint(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = values
        fields["k"] = AppAuth.cockpitToken
        request.httpBody = fields
            .sorted(by: { $0.key < $1.key })
            .map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CockpitAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error)
                ?? L10n.format("error.http", http.statusCode)
            throw CockpitAPIError.server(message)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CockpitAPIError.server(L10n.format("error.decode", error.localizedDescription))
        }
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

private struct ErrorEnvelope: Decodable { let error: String }
private struct AccountEnvelope: Decodable { let account: AccountSnapshot }
private struct LoginEnvelope: Decodable { let login: LoginSession }
private struct ResetEnvelope: Decodable {
    let outcome: String
    let account: AccountSnapshot
}
private struct DeleteAccountEnvelope: Decodable { let deleted: Bool }
