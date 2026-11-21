import Foundation
import WebKit

@MainActor
final class BrowserState: ObservableObject {
    @Published var title = ""
    @Published var currentURL: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var errorMessage: String?
    @Published var autofillStatus: AutofillStatus = .idle

    weak var webView: WKWebView?
    var pendingRequest: URLRequest?
    private var autofillStatusResetTask: Task<Void, Never>?
    var pendingDeviceCode: String? {
        didSet {
            guard pendingDeviceCode != nil else { return }
            setAutofillStatus(.waiting)
            fillPendingDeviceCodeIfPossible()
        }
    }

    func open(_ url: URL) {
        errorMessage = nil
        if let webView {
            webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData))
        } else {
            pendingRequest = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
        }
    }

    func open(_ request: URLRequest) {
        errorMessage = nil
        if let webView {
            webView.load(request)
        } else {
            pendingRequest = request
        }
    }

    func openDeviceLogin(code: String) {
        let normalized = DeviceCode.normalize(code)
        pendingDeviceCode = normalized.isEmpty ? nil : normalized
        if DeviceCodeAutofill.supports(webView?.url) { return }
        open(AppURLs.deviceLogin)
    }

    func fillPendingDeviceCodeIfPossible() {
        guard let code = pendingDeviceCode,
              let webView,
              webView.isLoading == false,
              DeviceCodeAutofill.supports(webView.url) else { return }

        setAutofillStatus(.waiting)
        DeviceCodeAutofill.fill(code: code, in: webView) { [weak self] started in
            guard let self, !started, self.pendingDeviceCode != nil else { return }
            self.setAutofillStatus(.notFound)
        }
    }

    func handleAutofillMessage(type: String) {
        switch type {
        case "codeFilled":
            setAutofillStatus(.filled, resetAfterNanoseconds: 4_000_000_000)
            pendingDeviceCode = nil
        case "codeNotFound":
            setAutofillStatus(.notFound)
        default:
            break
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func attach(_ webView: WKWebView, initialRequest: URLRequest) {
        self.webView = webView
        if let pendingRequest {
            open(pendingRequest)
        } else {
            open(initialRequest)
        }
        pendingRequest = nil
    }

    func update(from webView: WKWebView) {
        title = webView.title ?? ""
        currentURL = webView.url
        if !DeviceCodeAutofill.supports(webView.url) {
            setAutofillStatus(.idle)
        }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }

    private func setAutofillStatus(
        _ status: AutofillStatus,
        resetAfterNanoseconds delay: UInt64? = nil
    ) {
        autofillStatusResetTask?.cancel()
        autofillStatusResetTask = nil
        autofillStatus = status

        guard let delay else { return }
        autofillStatusResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.autofillStatus = .idle
        }
    }
}
