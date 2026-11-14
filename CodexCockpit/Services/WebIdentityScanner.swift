import Combine
import Foundation
import WebKit

@MainActor
final class WebIdentityScanner: ObservableObject {
    func scan(
        profiles: [WebProfile],
        onIdentity: (String, WebAccountIdentity) -> Void
    ) async {
        for profile in profiles {
            guard !Task.isCancelled else { return }
            if let identity = await detectIdentity(in: profile) {
                onIdentity(profile.id, identity)
            }
        }
    }

    private func detectIdentity(in profile: WebProfile) async -> WebAccountIdentity? {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ProfileDataStore.store(for: profile.dataStoreIdentifier)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(
            url: AppURLs.chatGPTSession,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        ))

        var attempts = 0
        while (webView.url == nil || webView.isLoading) && attempts < 150 {
            guard !Task.isCancelled else {
                webView.stopLoading()
                return nil
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                webView.stopLoading()
                return nil
            }
            attempts += 1
        }

        guard webView.url != nil, !webView.isLoading else {
            webView.stopLoading()
            return nil
        }
        defer { webView.stopLoading() }

        return await WebIdentityBridge.identityFromSessionDocument(in: webView)
    }
}
