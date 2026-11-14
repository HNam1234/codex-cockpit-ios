import WebKit
import XCTest
@testable import CodexCockpit

@MainActor
final class WebIdentityBridgeTests: XCTestCase {
    func testAsyncJavaScriptBridgeAwaitsIdentityPromise() async {
        let webView = WKWebView()

        let identity = await WebIdentityBridge.callIdentity(
            functionBody: """
            await new Promise(resolve => setTimeout(resolve, 10));
            return { name: 'Async Account', email: 'async@example.com' };
            """,
            in: webView
        )

        XCTAssertEqual(identity, WebAccountIdentity(name: "Async Account", email: "async@example.com"))
    }

    func testSessionDocumentBridgeReturnsOnlySanitizedIdentity() async {
        let webView = WKWebView()
        webView.loadHTMLString(
            """
            <html><body>{"user":{"name":" Safe User ","email":" safe@example.com "},"accessToken":"must-not-cross"}</body></html>
            """,
            baseURL: AppURLs.chatGPT
        )
        try? await Task.sleep(for: .milliseconds(200))

        let identity = await WebIdentityBridge.identityFromSessionDocument(in: webView)

        XCTAssertEqual(identity, WebAccountIdentity(name: "Safe User", email: "safe@example.com"))
    }
}
