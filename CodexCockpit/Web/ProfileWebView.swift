import SwiftUI
import UIKit
import WebKit

struct ProfileWebView: UIViewRepresentable {
    let dataStoreIdentifier: UUID
    let initialRequest: URLRequest
    @ObservedObject var state: BrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ProfileDataStore.store(for: dataStoreIdentifier)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isInspectable = false
        webView.scrollView.keyboardDismissMode = .interactive

        context.coordinator.observe(webView)
        state.attach(webView, initialRequest: initialRequest)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Intentionally empty. Browser state is driven by KVO/navigation
        // callbacks. Publishing ObservableObject changes from this SwiftUI
        // update callback creates a render loop and can exhaust the process.
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving(webView)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let state: BrowserState
        private var observations: [NSKeyValueObservation] = []

        init(state: BrowserState) {
            self.state = state
        }

        func observe(_ webView: WKWebView) {
            let update: (WKWebView) -> Void = { [weak self] webView in
                guard let self else { return }
                Task { @MainActor in self.state.update(from: webView) }
            }
            observations = [
                webView.observe(\.title, options: [.new]) { webView, _ in update(webView) },
                webView.observe(\.url, options: [.new]) { webView, _ in update(webView) },
                webView.observe(\.canGoBack, options: [.new]) { webView, _ in update(webView) },
                webView.observe(\.canGoForward, options: [.new]) { webView, _ in update(webView) },
                webView.observe(\.isLoading, options: [.new]) { webView, _ in update(webView) },
                webView.observe(\.estimatedProgress, options: [.new]) { webView, _ in update(webView) }
            ]
        }

        func stopObserving(_ webView: WKWebView) {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.cancel)
                return
            }
            if ["https", "about", "data", "blob"].contains(scheme) {
                decisionHandler(.allow)
            } else if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.update(from: webView)
            guard webView.url?.host == AppURLs.deviceLogin.host,
                  webView.url?.path.hasPrefix(AppURLs.deviceLogin.path) == true,
                  let code = state.pendingDeviceCode else { return }
            state.pendingDeviceCode = nil

            let encoded = code
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let script = """
            (() => {
              const input = document.querySelector('input[autocomplete="one-time-code"], input[name*="code" i], input[id*="code" i], input[type="text"]');
              if (!input) return false;
              const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
              setter.call(input, '\(encoded)');
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
              input.focus();
              return true;
            })();
            """
            webView.evaluateJavaScript(script)
        }
    }
}
