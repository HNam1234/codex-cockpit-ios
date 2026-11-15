import Foundation
import XCTest
@testable import CodexCockpit

@MainActor
final class DirectOAuthFlowTests: XCTestCase {
    private let hostID = "urn:uuid:00000000-0000-4000-8000-000000000001"
    private let state = "state-direct-123"
    private let nonce = "nonce-direct-123"
    private let verifier = String(repeating: "v", count: 64)

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
