import Foundation
import WebKit

@MainActor
enum WebIdentityBridge {
    static func callIdentity(
        functionBody: String,
        in webView: WKWebView
    ) async -> WebAccountIdentity? {
        do {
            let value = try await webView.callAsyncJavaScript(
                functionBody,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return WebAccountIdentity(javaScriptValue: value)
        } catch {
            return nil
        }
    }

    static func detectChatGPTSession(in webView: WKWebView) async -> WebAccountIdentity? {
        await callIdentity(
            functionBody: """
            try {
              const response = await fetch('/api/auth/session', {
                credentials: 'same-origin',
                cache: 'no-store'
              });
              if (!response.ok) return null;
              const session = await response.json();
              return sanitizedIdentity(session && session.user);
            } catch (_) {
              return null;
            }

            function sanitizedIdentity(user) {
              if (!user) return null;
              const name = typeof user.name === 'string' ? user.name.trim() : '';
              const email = typeof user.email === 'string' ? user.email.trim() : '';
              return name || email ? { name: name || null, email: email || null } : null;
            }
            """,
            in: webView
        )
    }

    static func identityFromSessionDocument(in webView: WKWebView) async -> WebAccountIdentity? {
        await callIdentity(
            functionBody: """
            try {
              const session = JSON.parse(document.body.innerText);
              const user = session && session.user;
              if (!user) return null;
              const name = typeof user.name === 'string' ? user.name.trim() : '';
              const email = typeof user.email === 'string' ? user.email.trim() : '';
              return name || email ? { name: name || null, email: email || null } : null;
            } catch (_) {
              return null;
            }
            """,
            in: webView
        )
    }
}
