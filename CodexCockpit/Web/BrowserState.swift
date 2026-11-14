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
    @Published private(set) var deviceCode: String?

    weak var webView: WKWebView?
    var pendingRequest: URLRequest?
    var pendingDeviceCode: String?
    private var deviceCodeFillTask: Task<Void, Never>?

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
        prepareDeviceCode(code)
        open(AppURLs.deviceLogin)
    }

    func prepareDeviceCode(_ rawCode: String) {
        let code = DeviceCodeAssistant.normalized(rawCode)
        deviceCode = code.isEmpty ? nil : code
        pendingDeviceCode = deviceCode
        if let webView,
           webView.url?.host == AppURLs.deviceLogin.host,
           webView.url?.path.hasPrefix(AppURLs.deviceLogin.path) == true,
           !webView.isLoading {
            fillPendingDeviceCode(in: webView)
        }
    }

    func markDeviceCodeFilled(_ code: String) {
        guard pendingDeviceCode == code else { return }
        pendingDeviceCode = nil
    }

    func clearDeviceCode() {
        cancelDeviceCodeFill()
        deviceCode = nil
        pendingDeviceCode = nil
    }

    func fillPendingDeviceCode(in webView: WKWebView) {
        guard let code = pendingDeviceCode else { return }
        deviceCodeFillTask?.cancel()
        deviceCodeFillTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            if await DeviceCodeAssistant.fill(code, in: webView) {
                _ = await DeviceCodeAssistant.submit(in: webView)
                self.markDeviceCodeFilled(code)
            }
        }
    }

    func retryDeviceCodeFill() {
        guard let code = deviceCode else { return }
        pendingDeviceCode = code
        if let webView,
           webView.url?.host == AppURLs.deviceLogin.host,
           webView.url?.path.hasPrefix(AppURLs.deviceLogin.path) == true {
            fillPendingDeviceCode(in: webView)
        } else {
            open(AppURLs.deviceLogin)
        }
    }

    func cancelDeviceCodeFill() {
        deviceCodeFillTask?.cancel()
        deviceCodeFillTask = nil
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
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }
}
