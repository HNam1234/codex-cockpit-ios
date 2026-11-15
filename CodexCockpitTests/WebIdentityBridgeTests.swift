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
        let navigation = NavigationWaiter()
        webView.navigationDelegate = navigation
        webView.loadHTMLString(
            """
            <html><body>{"user":{"name":" Safe User ","email":" safe@example.com "},"accessToken":"must-not-cross"}</body></html>
            """,
            baseURL: AppURLs.chatGPT
        )
        await fulfillment(of: [navigation.didFinish], timeout: 15)

        let identity = await WebIdentityBridge.identityFromSessionDocument(in: webView)

        XCTAssertEqual(identity, WebAccountIdentity(name: "Safe User", email: "safe@example.com"))
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    let didFinish = XCTestExpectation(description: "WebView navigation finished")

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish.fulfill()
    }
}
