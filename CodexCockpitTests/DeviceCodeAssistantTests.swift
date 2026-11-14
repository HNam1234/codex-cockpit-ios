import WebKit
import XCTest
@testable import CodexCockpit

@MainActor
final class DeviceCodeAssistantTests: XCTestCase {
    func testNormalizationProducesOfficialDeviceCodeShape() {
        XCTAssertEqual(DeviceCodeAssistant.normalized(" abcd efgh-12! "), "ABCDEFGH-12")
        XCTAssertEqual(DeviceCodeAssistant.normalized("é_"), "")
    }

    func testFillWaitsForDelayedCodeInputAndFocusesIt() async throws {
        let webView = WKWebView()
        let navigation = DeviceCodeNavigationWaiter()
        webView.navigationDelegate = navigation
        webView.loadHTMLString(
            """
            <html><body><script>
              setTimeout(() => {
                const input = document.createElement('input');
                input.name = 'user_code';
                document.body.appendChild(input);
              }, 250);
            </script></body></html>
            """,
            baseURL: AppURLs.deviceLogin
        )
        await fulfillment(of: [navigation.didFinish], timeout: 5)

        let filled = await DeviceCodeAssistant.fill(
            "abcd-efgh",
            in: webView,
            attempts: 10,
            retryDelay: .milliseconds(100)
        )
        let result = try await webView.callAsyncJavaScript(
            "return { value: document.querySelector('input').value, focused: document.activeElement === document.querySelector('input') };",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertTrue(filled)
        XCTAssertEqual(result?["value"] as? String, "ABCD-EFGH")
        XCTAssertEqual(result?["focused"] as? Bool, true)
    }

    func testFillReturnsFalseWhenPageHasNoCodeInput() async {
        let webView = WKWebView()

        let filled = await DeviceCodeAssistant.fill(
            "ABCD-EFGH",
            in: webView,
            attempts: 1,
            retryDelay: .zero
        )

        XCTAssertFalse(filled)
    }

    func testSubmitClicksEnabledButtonInCodeForm() async throws {
        let webView = WKWebView()
        let navigation = DeviceCodeNavigationWaiter()
        webView.navigationDelegate = navigation
        webView.loadHTMLString(
            """
            <html><body>
              <form onsubmit="window.deviceCodeSubmitted = true; event.preventDefault();">
                <input name="user_code" value="ABCD-EFGH">
                <button type="submit">Continue</button>
              </form>
            </body></html>
            """,
            baseURL: AppURLs.deviceLogin
        )
        await fulfillment(of: [navigation.didFinish], timeout: 5)

        let submitted = await DeviceCodeAssistant.submit(
            in: webView,
            attempts: 1,
            retryDelay: .zero
        )
        let pageRecordedSubmit = try await webView.callAsyncJavaScript(
            "return window.deviceCodeSubmitted === true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool

        XCTAssertTrue(submitted)
        XCTAssertEqual(pageRecordedSubmit, true)
    }

    func testSubmitReturnsFalseWithoutCodeForm() async {
        let webView = WKWebView()

        let submitted = await DeviceCodeAssistant.submit(
            in: webView,
            attempts: 1,
            retryDelay: .zero
        )

        XCTAssertFalse(submitted)
    }

    func testBrowserKeepsCodeVisibleAfterFillAndCanRetry() {
        let browser = BrowserState()
        browser.prepareDeviceCode("abcd-efgh")

        XCTAssertEqual(browser.deviceCode, "ABCD-EFGH")
        XCTAssertEqual(browser.pendingDeviceCode, "ABCD-EFGH")

        browser.markDeviceCodeFilled("ABCD-EFGH")
        XCTAssertEqual(browser.deviceCode, "ABCD-EFGH")
        XCTAssertNil(browser.pendingDeviceCode)

        browser.retryDeviceCodeFill()
        XCTAssertEqual(browser.pendingDeviceCode, "ABCD-EFGH")
        XCTAssertEqual(browser.pendingRequest?.url, AppURLs.deviceLogin)
    }
}

@MainActor
private final class DeviceCodeNavigationWaiter: NSObject, WKNavigationDelegate {
    let didFinish = XCTestExpectation(description: "Device-code page finished loading")

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish.fulfill()
    }
}
