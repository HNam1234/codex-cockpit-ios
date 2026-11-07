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
    var pendingURL: URL?
    var pendingDeviceCode: String?

    func open(_ url: URL) {
        errorMessage = nil
        if let webView {
            webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData))
        } else {
            pendingURL = url
        }
    }

    func openDeviceLogin(code: String) {
        pendingDeviceCode = code.isEmpty ? nil : code
        open(AppURLs.deviceLogin)
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func attach(_ webView: WKWebView, initialURL: URL) {
        self.webView = webView
        open(pendingURL ?? initialURL)
        pendingURL = nil
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
