import XCTest
@testable import CodexCockpit

@MainActor
final class CockpitOAuthRelayTests: XCTestCase {
    private let directAuthorizeURL = "https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_test&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&state=state-123&code_challenge=challenge-123&code_challenge_method=S256"

    func testPrepareAcceptsCockpitHostedAuthorizationURL() throws {
        let hostedURL = try makeHostedURL(authorizeURL: directAuthorizeURL)

        let attempt = try CockpitOAuthRelay.prepare(hostedURL.absoluteString)

        XCTAssertEqual(attempt.authorizationURL, hostedURL)
        XCTAssertEqual(attempt.callbackScheme, "http")
        XCTAssertEqual(attempt.callbackHost, "localhost")
        XCTAssertEqual(attempt.callbackPort, 1455)
        XCTAssertEqual(attempt.callbackPath, "/auth/callback")
        XCTAssertEqual(attempt.state, "state-123")
    }

    func testPrepareAcceptsDirectAuthorizeURLWithIPv4Loopback() throws {
        let url = directAuthorizeURL
            .replacingOccurrences(of: "localhost", with: "127.0.0.1")
            .replacingOccurrences(of: "1455", with: "9876")

        let attempt = try CockpitOAuthRelay.prepare(url)

        XCTAssertEqual(attempt.authorizationURL.absoluteString, url)
        XCTAssertEqual(attempt.callbackHost, "127.0.0.1")
        XCTAssertEqual(attempt.callbackPort, 9876)
        XCTAssertEqual(attempt.state, "state-123")
    }

    func testPrepareRejectsMalformedHostedAndDeceptiveHosts() throws {
        let cases = [
            "https://chatgpt.com.evil.example/codex/desktop-auth?authorize_url=x",
            "https://chatgpt.com/codex/not-desktop-auth?authorize_url=x",
            "http://chatgpt.com/codex/desktop-auth?authorize_url=x",
            "https://user@chatgpt.com/codex/desktop-auth?authorize_url=x",
            "https://chatgpt.com/codex/desktop-auth?authorize_url=x#fragment",
            "https://auth.openai.com.evil.example/oauth/authorize?response_type=code",
            "https://auth.openai.com/oauth/not-authorize?response_type=code",
            "http://auth.openai.com/oauth/authorize?response_type=code",
            "https://user@auth.openai.com/oauth/authorize?response_type=code",
            "https://auth.openai.com/oauth/authorize?response_type=code#fragment"
        ]

        for value in cases {
            assertPrepareRejected(value)
        }

        assertPrepareRejected(try makeHostedURL(authorizeURL: "not-a-url").absoluteString)
        assertPrepareRejected("https://chatgpt.com/codex/desktop-auth")
        assertPrepareRejected("https://chatgpt.com/codex/desktop-auth?authorize_url=x&authorize_url=y")
    }

    func testPrepareRejectsMissingDuplicateOrInvalidAuthorizationParameters() {
        let valid = directAuthorizeURL
        let cases = [
            valid.replacingOccurrences(of: "client_id=app_test&", with: ""),
            valid + "&client_id=second",
            valid.replacingOccurrences(of: "client_id=app_test", with: "client_id="),
            valid.replacingOccurrences(of: "response_type=code", with: "response_type=token"),
            valid + "&response_type=code",
            valid.replacingOccurrences(of: "state=state-123", with: "state="),
            valid + "&state=second",
            valid.replacingOccurrences(of: "code_challenge=challenge-123", with: "code_challenge="),
            valid + "&code_challenge=second",
            valid.replacingOccurrences(of: "code_challenge_method=S256", with: "code_challenge_method=plain"),
            valid + "&code_challenge_method=S256",
            valid.replacingOccurrences(of: "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&", with: ""),
            valid + "&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback"
        ]

        for value in cases {
            assertPrepareRejected(value)
        }
    }

    func testPrepareRejectsUnsafeRedirectURIs() {
        let redirects = [
            "https://localhost:1455/auth/callback",
            "http://example.com:1455/auth/callback",
            "http://localhost/auth/callback",
            "http://localhost:0/auth/callback",
            "http://localhost:65536/auth/callback",
            "http://localhost:1455/wrong",
            "http://localhost:1455/auth/callback?extra=1",
            "http://localhost:1455/auth/callback#fragment",
            "http://user@localhost:1455/auth/callback"
        ]

        for redirect in redirects {
            assertPrepareRejected(replacingRedirect(in: directAuthorizeURL, with: redirect))
        }
    }

    func testInspectCallbackCapturesOnlyTheExpectedCallback() throws {
        let attempt = try CockpitOAuthRelay.prepare(directAuthorizeURL)
        let callbackURL = try XCTUnwrap(
            URL(string: "http://localhost:1455/auth/callback?code=authorization-code&state=state-123")
        )

        XCTAssertEqual(
            CockpitOAuthRelay.inspectCallback(callbackURL, for: attempt),
            .captured(CockpitOAuthCallback(url: callbackURL))
        )
    }

    func testInspectCallbackIgnoresOrdinaryHTTPSNavigation() throws {
        let attempt = try CockpitOAuthRelay.prepare(directAuthorizeURL)
        let ordinaryURL = try XCTUnwrap(URL(string: "https://auth.openai.com/account/select"))

        XCTAssertEqual(CockpitOAuthRelay.inspectCallback(ordinaryURL, for: attempt), .notCallback)
    }

    func testInspectCallbackRejectsLookalikesAndMismatches() throws {
        let attempt = try CockpitOAuthRelay.prepare(directAuthorizeURL)
        let cases = [
            "http://localhost.evil.example:1455/auth/callback?code=authorization-code&state=state-123",
            "http://127.0.0.1:1455/auth/callback?code=authorization-code&state=state-123",
            "http://localhost:9876/auth/callback?code=authorization-code&state=state-123",
            "http://localhost:1455/wrong?code=authorization-code&state=state-123",
            "https://localhost:1455/auth/callback?code=authorization-code&state=state-123",
            "http://user@localhost:1455/auth/callback?code=authorization-code&state=state-123",
            "http://localhost:1455/auth/callback?code=authorization-code&state=state-123#fragment",
            "http://localhost:1455/auth/callback?state=state-123",
            "http://localhost:1455/auth/callback?code=authorization-code&code=second&state=state-123",
            "http://localhost:1455/auth/callback?code=authorization-code",
            "http://localhost:1455/auth/callback?code=authorization-code&state=state-123&state=second",
            "http://localhost:1455/auth/callback?code=&state=state-123",
            "http://localhost:1455/auth/callback?code=authorization-code&state=state-124"
        ]

        for value in cases {
            let url = try XCTUnwrap(URL(string: value))
            let result = CockpitOAuthRelay.inspectCallback(url, for: attempt)
            guard case let .rejected(error) = result else {
                return XCTFail("Expected callback rejection for \(url.host ?? "unknown host")")
            }
            XCTAssertTrue(error.localizationKey.hasPrefix("oauth.relay.error."))
            XCTAssertFalse(error.localizationKey.contains("authorization-code"))
            XCTAssertFalse(error.localizationKey.contains("state-12"))
        }
    }

    func testBrowserStatePreparesAndCapturesCockpitOAuth() throws {
        let attempt = try CockpitOAuthRelay.prepare(directAuthorizeURL)
        let callbackURL = try XCTUnwrap(
            URL(string: "http://localhost:1455/auth/callback?code=authorization-code&state=state-123")
        )
        let browser = BrowserState()

        browser.prepareCockpitOAuth(attempt)

        XCTAssertEqual(browser.cockpitOAuthAttempt, attempt)
        XCTAssertNil(browser.capturedCockpitOAuthCallback)
        XCTAssertEqual(browser.pendingRequest?.url, attempt.authorizationURL)
        XCTAssertTrue(browser.handleCockpitOAuthNavigation(callbackURL))
        XCTAssertNil(browser.cockpitOAuthAttempt)
        XCTAssertEqual(browser.capturedCockpitOAuthCallback?.url, callbackURL)
        XCTAssertNil(browser.errorMessage)
    }

    func testBrowserStateCancelsMismatchButKeepsAttemptRetryable() throws {
        let attempt = try CockpitOAuthRelay.prepare(directAuthorizeURL)
        let wrongStateURL = try XCTUnwrap(
            URL(string: "http://localhost:1455/auth/callback?code=authorization-code&state=state-124")
        )
        let browser = BrowserState()
        browser.prepareCockpitOAuth(attempt)

        XCTAssertTrue(browser.handleCockpitOAuthNavigation(wrongStateURL))
        XCTAssertEqual(browser.cockpitOAuthAttempt, attempt)
        XCTAssertNil(browser.capturedCockpitOAuthCallback)
        XCTAssertEqual(browser.errorMessage, CockpitOAuthRelayError.stateMismatch.localizationKey)
    }

    func testBrowserStateAllowsOrdinaryNavigationAndCanClearOAuthState() throws {
        let attempt = try CockpitOAuthRelay.prepare(directAuthorizeURL)
        let ordinaryURL = try XCTUnwrap(URL(string: "https://auth.openai.com/account/select"))
        let callbackURL = try XCTUnwrap(
            URL(string: "http://localhost:1455/auth/callback?code=authorization-code&state=state-123")
        )
        let browser = BrowserState()
        browser.prepareCockpitOAuth(attempt)

        XCTAssertFalse(browser.handleCockpitOAuthNavigation(ordinaryURL))
        XCTAssertEqual(browser.cockpitOAuthAttempt, attempt)

        XCTAssertTrue(browser.handleCockpitOAuthNavigation(callbackURL))
        browser.clearCockpitOAuth()

        XCTAssertNil(browser.cockpitOAuthAttempt)
        XCTAssertNil(browser.capturedCockpitOAuthCallback)
        XCTAssertNil(browser.errorMessage)
    }

    private func makeHostedURL(authorizeURL: String) throws -> URL {
        var components = URLComponents(string: "https://chatgpt.com/codex/desktop-auth")!
        components.queryItems = [URLQueryItem(name: "authorize_url", value: authorizeURL)]
        return try XCTUnwrap(components.url)
    }

    private func replacingRedirect(in authorizeURL: String, with redirect: String) -> String {
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = components.queryItems?.map { item in
            item.name == "redirect_uri" ? URLQueryItem(name: item.name, value: redirect) : item
        }
        return components.url!.absoluteString
    }

    private func assertPrepareRejected(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try CockpitOAuthRelay.prepare(value), file: file, line: line) { error in
            guard let relayError = error as? CockpitOAuthRelayError else {
                return XCTFail("Expected a relay validation error", file: file, line: line)
            }
            XCTAssertTrue(relayError.localizationKey.hasPrefix("oauth.relay.error."), file: file, line: line)
        }
    }
}
