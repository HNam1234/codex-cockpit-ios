import SwiftUI
import UIKit
import WebKit

struct ProfileWebView: UIViewRepresentable {
    let dataStoreIdentifier: UUID
    let initialRequest: URLRequest
    @ObservedObject var state: BrowserState
    var onIdentityDetected: ((WebAccountIdentity) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onIdentityDetected: onIdentityDetected)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ProfileDataStore.store(for: dataStoreIdentifier)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(DeviceCodeAutofill.userScript)
        let autofillProxy = WeakScriptMessageHandler(delegate: context.coordinator)
        configuration.userContentController.add(
            autofillProxy,
            contentWorld: .defaultClient,
            name: DeviceCodeAutofill.messageHandlerName
        )
        context.coordinator.autofillProxy = autofillProxy

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
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: DeviceCodeAutofill.messageHandlerName,
            contentWorld: .defaultClient
        )
        coordinator.autofillProxy = nil
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let state: BrowserState
        private let onIdentityDetected: ((WebAccountIdentity) -> Void)?
        private var observations: [NSKeyValueObservation] = []
        var autofillProxy: WeakScriptMessageHandler?

        init(
            state: BrowserState,
            onIdentityDetected: ((WebAccountIdentity) -> Void)?
        ) {
            self.state = state
            self.onIdentityDetected = onIdentityDetected
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
            probeChatGPTIdentity(in: webView)
            state.fillPendingDeviceCodeIfPossible()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == DeviceCodeAutofill.messageHandlerName,
                  DeviceCodeAutofill.supports(message.webView?.url),
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            state.handleAutofillMessage(type: type)
        }

        private func probeChatGPTIdentity(in webView: WKWebView) {
            guard webView.url?.host?.lowercased() == AppURLs.chatGPT.host else { return }
            Task { @MainActor [weak self, weak webView] in
                guard let webView,
                      let identity = await WebIdentityBridge.detectChatGPTSession(in: webView) else { return }
                self?.onIdentityDetected?(identity)
            }
        }
    }
}
