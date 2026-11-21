import UIKit
import WebKit

@MainActor
final class WebViewPool {
    static let shared = WebViewPool()

    enum NavigationDecision: Equatable {
        case keep
        case load
        case reload
    }

    private final class Entry {
        let profile: WebProfile
        let webView: WKWebView
        let state: BrowserState
        let sessionDelegate: SessionDelegate
        let messageProxy: WeakScriptMessageHandler
        weak var container: UIView?
        var lastUsed = Date()

        init(
            profile: WebProfile,
            webView: WKWebView,
            state: BrowserState,
            sessionDelegate: SessionDelegate,
            messageProxy: WeakScriptMessageHandler
        ) {
            self.profile = profile
            self.webView = webView
            self.state = state
            self.sessionDelegate = sessionDelegate
            self.messageProxy = messageProxy
        }
    }

    private let capacity = 2
    private var entries: [String: Entry] = [:]
    private var states: [String: BrowserState] = [:]
    private var visibleProfileIDs: Set<String> = []
    private var memoryWarningObserver: NSObjectProtocol?

    private init(notificationCenter: NotificationCenter = .default) {
        memoryWarningObserver = notificationCenter.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evictDetachedEntries()
            }
        }
    }

    func browserState(for profile: WebProfile) -> BrowserState {
        if let state = states[profile.id] { return state }
        let state = BrowserState()
        states[profile.id] = state
        return state
    }

    func webView(for profile: WebProfile) -> (WKWebView, BrowserState) {
        if let entry = entries[profile.id] {
            entry.lastUsed = Date()
            return (entry.webView, entry.state)
        }

        pruneForInsertion(excluding: profile.id)

        let state = browserState(for: profile)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ProfileDataStore.store(for: profile.dataStoreIdentifier)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(DeviceCodeAutofill.userScript)

        let sessionDelegate = SessionDelegate(state: state)
        let messageProxy = WeakScriptMessageHandler(delegate: sessionDelegate)
        configuration.userContentController.add(
            messageProxy,
            contentWorld: .defaultClient,
            name: DeviceCodeAutofill.messageHandlerName
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = sessionDelegate
        webView.uiDelegate = sessionDelegate
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isInspectable = false
        webView.scrollView.keyboardDismissMode = .interactive

        sessionDelegate.observe(webView)
        state.attach(webView)

        let entry = Entry(
            profile: profile,
            webView: webView,
            state: state,
            sessionDelegate: sessionDelegate,
            messageProxy: messageProxy
        )
        entries[profile.id] = entry
        return (webView, state)
    }

    func attach(
        profile: WebProfile,
        to container: UIView,
        initialRequest: URLRequest,
        onIdentityDetected: ((WebAccountIdentity) -> Void)?
    ) {
        let (webView, state) = webView(for: profile)
        guard let entry = entries[profile.id] else { return }

        entry.lastUsed = Date()
        entry.container = container
        entry.sessionDelegate.onIdentityDetected = onIdentityDetected

        let needsAttachment = webView.superview !== container
        if needsAttachment {
            webView.removeFromSuperview()
            webView.frame = container.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(webView)
            state.attach(webView)

            if let requestedURL = initialRequest.url {
                switch Self.shouldNavigate(
                    current: webView.url,
                    requested: requestedURL,
                    lastFinishedAt: entry.sessionDelegate.lastFinishedAt,
                    now: Date()
                ) {
                case .keep:
                    state.fillPendingDeviceCodeIfPossible()
                case .load:
                    state.open(initialRequest)
                case .reload:
                    webView.reload()
                }
            }
        }
    }

    func detach(profileID: String, from container: UIView) {
        guard let entry = entries[profileID], entry.container === container else { return }
        entry.webView.removeFromSuperview()
        entry.container = nil
        entry.sessionDelegate.onIdentityDetected = nil
        entry.lastUsed = Date()
    }

    func setVisible(_ visible: Bool, profileID: String) {
        if visible {
            visibleProfileIDs.insert(profileID)
        } else {
            visibleProfileIDs.remove(profileID)
            trimToCapacity()
        }
    }

    func prewarm(profile: WebProfile, url: URL = AppURLs.deviceLogin) {
        guard Self.prewarmEnabled else { return }
        let isNewEntry = entries[profile.id] == nil
        let (webView, state) = webView(for: profile)
        guard let entry = entries[profile.id], entry.container == nil else { return }

        entry.lastUsed = Date()
        if !isNewEntry, webView.isLoading { return }
        if !isNewEntry,
           let currentURL = webView.url,
           !Self.isBlank(currentURL),
           !DeviceCodeAutofill.supports(currentURL) {
            return
        }

        switch Self.shouldNavigate(
            current: webView.url,
            requested: url,
            lastFinishedAt: entry.sessionDelegate.lastFinishedAt,
            now: Date()
        ) {
        case .keep:
            return
        case .load:
            state.open(url)
        case .reload:
            webView.reload()
        }
    }

    nonisolated static func shouldNavigate(
        current: URL?,
        requested: URL,
        lastFinishedAt: Date?,
        now: Date
    ) -> NavigationDecision {
        guard let current, !isBlank(current) else { return .load }
        guard pageKey(current) == pageKey(requested) else { return .load }

        guard DeviceCodeAutofill.supports(requested) else { return .keep }
        guard let lastFinishedAt,
              now.timeIntervalSince(lastFinishedAt) < 10 * 60 else { return .reload }
        return .keep
    }

    func evict(profileID: String) {
        guard let entry = entries.removeValue(forKey: profileID) else { return }
        entry.webView.removeFromSuperview()
        entry.webView.stopLoading()
        entry.sessionDelegate.stopObserving()
        entry.webView.configuration.userContentController.removeScriptMessageHandler(
            forName: DeviceCodeAutofill.messageHandlerName,
            contentWorld: .defaultClient
        )
        entry.webView.navigationDelegate = nil
        entry.webView.uiDelegate = nil
        entry.state.webView = nil
    }

    private static var prewarmEnabled: Bool {
        let defaults = UserDefaults.standard
        let key = "CodexCockpit.prewarm.v1"
        return defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }

    nonisolated private static func isBlank(_ url: URL) -> Bool {
        url.absoluteString.lowercased() == "about:blank"
    }

    nonisolated private static func pageKey(_ url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        var path = url.path.isEmpty ? "/" : url.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return "\(host)\(path)"
    }

    private func pruneForInsertion(excluding profileID: String) {
        while entries.count >= capacity {
            guard let candidate = entries.values
                .filter({ $0.profile.id != profileID && !isVisible($0) })
                .min(by: { $0.lastUsed < $1.lastUsed }) else { return }
            evict(profileID: candidate.profile.id)
        }
    }

    private func evictDetachedEntries() {
        let profileIDs = entries.values
            .filter { !isVisible($0) }
            .map { $0.profile.id }
        profileIDs.forEach(evict)
    }

    private func trimToCapacity() {
        while entries.count > capacity {
            guard let candidate = entries.values
                .filter({ !isVisible($0) })
                .min(by: { $0.lastUsed < $1.lastUsed }) else { return }
            evict(profileID: candidate.profile.id)
        }
    }

    private func isVisible(_ entry: Entry) -> Bool {
        visibleProfileIDs.contains(entry.profile.id)
    }
}

@MainActor
private final class SessionDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private let state: BrowserState
    private var observations: [NSKeyValueObservation] = []
    var onIdentityDetected: ((WebAccountIdentity) -> Void)?
    var lastFinishedAt: Date?

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

    func stopObserving() {
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

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        state.errorMessage = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastFinishedAt = Date()
        state.update(from: webView)
        probeChatGPTIdentity(in: webView)
        state.fillPendingDeviceCodeIfPossible()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
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
