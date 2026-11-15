import Foundation
import XCTest
@testable import CodexCockpit

@MainActor
final class DirectOAuthFlowTests: XCTestCase {
    private let hostID = "urn:uuid:00000000-0000-4000-8000-000000000001"
    private let state = "state-direct-123"
    private let nonce = "nonce-direct-123"
    private let verifier = String(repeating: "v", count: 64)

    override func setUp() {
        super.setUp()
        DirectOAuthURLProtocolStub.reset()
    }

    override func tearDown() {
        DirectOAuthURLProtocolStub.reset()
        super.tearDown()
    }

    func testNewRegistrationBuildsOfficialDynamicClientAuthorization() throws {
        let attempt = try DirectOAuthFlow.makeAttempt(
            hostID: hostID,
            registration: nil,
            state: state,
            nonce: nonce,
            codeVerifier: verifier
        )
        let components = try XCTUnwrap(URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "auth.openai.com")
        XCTAssertEqual(components.path, "/api/accounts/authorize")
        XCTAssertEqual(values["client_id"], "dynamic_agent_client")
        XCTAssertEqual(values["agent_name_hint"], "Codex Cockpit")
        XCTAssertEqual(values["ext_agent_host_id"], hostID)
        XCTAssertEqual(values["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(values["state"], state)
        XCTAssertEqual(values["nonce"], nonce)
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["resource"], "https://api.openai.com/v1")
        XCTAssertTrue(values["scope"]?.contains("openid") == true)
        XCTAssertTrue(values["scope"]?.contains("email") == true)
        XCTAssertNotEqual(values["code_challenge"], verifier)
        XCTAssertEqual(attempt.requestedClientID, "dynamic_agent_client")
        XCTAssertNil(attempt.expectedSubject)
    }

    func testReturningRegistrationReusesClientAndIdentityHints() throws {
        let registration = fixtureRegistration()

        let attempt = try DirectOAuthFlow.makeAttempt(
            hostID: hostID,
            registration: registration,
            state: state,
            nonce: nonce,
            codeVerifier: verifier
        )
        let components = try XCTUnwrap(URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["client_id"], registration.clientID)
        XCTAssertEqual(values["id_token_hint"], registration.idToken)
        XCTAssertEqual(values["login_hint"], registration.email)
        XCTAssertNil(values["agent_name_hint"])
        XCTAssertEqual(attempt.expectedSubject, registration.subject)
    }

    func testCallbackCapturesExactLoopbackAndIssuedClient() throws {
        let attempt = try newAttempt()
        let callbackURL = try XCTUnwrap(URL(
            string: "http://127.0.0.1:1455/auth/callback?code=auth-code&state=state-direct-123&client_id=oaiapp_issued"
        ))

        XCTAssertEqual(
            DirectOAuthFlow.inspectCallback(callbackURL, for: attempt),
            .captured(DirectOAuthCallback(code: "auth-code", issuedClientID: "oaiapp_issued"))
        )
    }

    func testCallbackRejectsStateHostAndReturningClientMismatch() throws {
        let newAttempt = try newAttempt()
        let unsafeValues = [
            "http://localhost:1455/auth/callback?code=auth-code&state=state-direct-123&client_id=oaiapp_issued",
            "http://127.0.0.1:1456/auth/callback?code=auth-code&state=state-direct-123&client_id=oaiapp_issued",
            "http://127.0.0.1:1455/auth/callback?code=auth-code&state=wrong&client_id=oaiapp_issued",
            "http://127.0.0.1:1455/auth/callback?code=auth-code&state=state-direct-123"
        ]
        for value in unsafeValues {
            let url = try XCTUnwrap(URL(string: value))
            guard case .rejected = DirectOAuthFlow.inspectCallback(url, for: newAttempt) else {
                return XCTFail("Expected rejection for \(url.host ?? "callback")")
            }
        }

        let returningAttempt = try DirectOAuthFlow.makeAttempt(
            hostID: hostID,
            registration: fixtureRegistration(),
            state: state,
            nonce: nonce,
            codeVerifier: verifier
        )
        let wrongClient = try XCTUnwrap(URL(
            string: "http://127.0.0.1:1455/auth/callback?code=auth-code&state=state-direct-123&client_id=oaiapp_other"
        ))
        XCTAssertEqual(
            DirectOAuthFlow.inspectCallback(wrongClient, for: returningAttempt),
            .rejected(.clientMismatch)
        )
    }

    func testBrowserStateCapturesDirectOAuthWithoutOpeningLoopback() throws {
        let attempt = try newAttempt()
        let callbackURL = try XCTUnwrap(URL(
            string: "http://127.0.0.1:1455/auth/callback?code=auth-code&state=state-direct-123&client_id=oaiapp_issued"
        ))
        let browser = BrowserState()

        browser.prepareDirectOAuth(attempt)

        XCTAssertEqual(browser.directOAuthAttempt, attempt)
        XCTAssertEqual(browser.pendingRequest?.url, attempt.authorizationURL)
        XCTAssertTrue(browser.handleDirectOAuthNavigation(callbackURL))
        XCTAssertNil(browser.directOAuthAttempt)
        XCTAssertEqual(browser.capturedDirectOAuth?.attempt, attempt)
        XCTAssertEqual(browser.capturedDirectOAuth?.callback.issuedClientID, "oaiapp_issued")
    }

    func testTokenExchangeRepeatsOfficialResourceParameter() async throws {
        let recorder = DirectOAuthRequestRecorder()
        DirectOAuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data(#"{"error":"invalid_request"}"#.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectOAuthURLProtocolStub.self]
        let client = DirectOAuthClient(session: URLSession(configuration: configuration))
        let capture = DirectOAuthCapture(
            attempt: try newAttempt(),
            callback: DirectOAuthCallback(code: "auth-code", issuedClientID: "oaiapp_issued")
        )

        do {
            _ = try await client.exchange(capture: capture, profileID: "3", previous: nil)
            XCTFail("Expected the controlled token endpoint to reject the request")
        } catch let error as DirectOAuthError {
            XCTAssertEqual(error, .tokenExchangeFailed(400))
        }

        let request = try XCTUnwrap(recorder.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let items = URLComponents(string: "?\(body)")?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(request.url, DirectOAuthFlow.tokenEndpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(values["grant_type"], "authorization_code")
        XCTAssertEqual(values["client_id"], "oaiapp_issued")
        XCTAssertEqual(values["code"], "auth-code")
        XCTAssertEqual(values["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(values["code_verifier"], verifier)
        XCTAssertEqual(values["resource"], "https://api.openai.com/v1")
    }

    func testVerifiedIdentityRequiresVerifiedEmailAndStableSubject() throws {
        let valid: [String: Any] = [
            "iss": "https://auth.openai.com",
            "aud": "oaiapp_issued",
            "sub": "subject-123",
            "email": "person@example.com",
            "email_verified": true,
            "nonce": nonce,
            "iat": Date().timeIntervalSince1970 - 10,
            "exp": Date().timeIntervalSince1970 + 300
        ]

        let identity = try OpenAIIDTokenVerifier.validateClaims(
            valid,
            clientID: "oaiapp_issued",
            nonce: nonce,
            now: Date()
        )

        XCTAssertEqual(identity.subject, "subject-123")
        XCTAssertEqual(identity.email, "person@example.com")

        var unverified = valid
        unverified["email_verified"] = false
        XCTAssertThrowsError(try OpenAIIDTokenVerifier.validateClaims(
            unverified,
            clientID: "oaiapp_issued",
            nonce: nonce,
            now: Date()
        ))
    }

    private func newAttempt() throws -> DirectOAuthAttempt {
        try DirectOAuthFlow.makeAttempt(
            hostID: hostID,
            registration: nil,
            state: state,
            nonce: nonce,
            codeVerifier: verifier
        )
    }

    private func fixtureRegistration() -> DirectOAuthRegistration {
        DirectOAuthRegistration(
            profileID: "1",
            clientID: "oaiapp_existing",
            subject: "subject-existing",
            email: "existing@example.com",
            name: "Existing Person",
            idToken: "header.payload.signature",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            scopes: ["openid", "email"],
            expiresAt: 2_000_000_000,
            earliestRefreshAt: nil
        )
    }
}

private final class DirectOAuthURLProtocolStub: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class DirectOAuthRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storage }
    }

    func append(_ request: URLRequest) {
        var snapshot = request
        if snapshot.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }

            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            snapshot.httpBody = body
        }
        lock.withLock { storage.append(snapshot) }
    }
}
