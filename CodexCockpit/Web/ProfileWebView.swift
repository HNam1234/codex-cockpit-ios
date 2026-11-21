import SwiftUI
import UIKit

struct ProfileWebView: UIViewRepresentable {
    let profile: WebProfile
    let initialRequest: URLRequest
    @ObservedObject var state: BrowserState
    var onIdentityDetected: ((WebAccountIdentity) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(profileID: profile.id)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear

        let (_, pooledState) = WebViewPool.shared.webView(for: profile)
        assert(pooledState === state, "ProfileWebView must use the BrowserState owned by WebViewPool")
        WebViewPool.shared.attach(
            profile: profile,
            to: container,
            initialRequest: initialRequest,
            onIdentityDetected: onIdentityDetected
        )
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        WebViewPool.shared.attach(
            profile: profile,
            to: container,
            initialRequest: initialRequest,
            onIdentityDetected: onIdentityDetected
        )
    }

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
        WebViewPool.shared.detach(profileID: coordinator.profileID, from: container)
    }

    final class Coordinator {
        let profileID: String

        init(profileID: String) {
            self.profileID = profileID
        }
    }
}
