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

    weak var webView: WKWebView?
    var pendingRequest: URLRequest?
    var pendingDeviceCode: String?

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
        open(AppURLs.deviceLogin)
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
