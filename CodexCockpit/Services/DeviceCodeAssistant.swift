import Foundation
import WebKit

@MainActor
enum DeviceCodeAssistant {
    private static let allowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
    )

    static func normalized(_ rawValue: String) -> String {
        String(
            rawValue
                .uppercased()
                .filter { character in
                    character.unicodeScalars.count == 1
                        && character.unicodeScalars.first.map { allowedCharacters.contains($0) } == true
                }
        )
    }

    static func fill(
        _ rawCode: String,
        in webView: WKWebView,
        attempts: Int = 20,
        retryDelay: Duration = .milliseconds(150)
    ) async -> Bool {
        let code = normalized(rawCode)
        guard !code.isEmpty else { return false }

        for attempt in 0..<max(1, attempts) {
            guard !Task.isCancelled else { return false }
            do {
                let value = try await webView.callAsyncJavaScript(
                    """
                    const input = document.querySelector(
                      'input[autocomplete="one-time-code"], input[name="user_code"], input[name*="code" i], input[id*="code" i], input[placeholder*="code" i], input[type="text"]'
                    );
                    if (!input) return false;
                    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
                    setter.call(input, code);
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.dispatchEvent(new Event('change', { bubbles: true }));
                    input.focus();
                    return input.value === code;
                    """,
                    arguments: ["code": code],
                    in: nil,
                    contentWorld: .page
                )
                if value as? Bool == true { return true }
            } catch {
                // The page may still be redirecting or constructing its form.
            }
            if attempt + 1 < max(1, attempts) {
                do {
                    try await Task.sleep(for: retryDelay)
                } catch {
                    return false
                }
            }
        }
        return false
    }

    static func submit(
        in webView: WKWebView,
        attempts: Int = 12,
        retryDelay: Duration = .milliseconds(150)
    ) async -> Bool {
        for attempt in 0..<max(1, attempts) {
            guard !Task.isCancelled else { return false }
            do {
                let value = try await webView.callAsyncJavaScript(
                    """
                    const input = document.querySelector(
                      'input[autocomplete="one-time-code"], input[name="user_code"], input[name*="code" i], input[id*="code" i], input[placeholder*="code" i], input[type="text"]'
                    );
                    if (!input) return false;
                    const form = input.form || input.closest('form');
                    if (!form) return false;
                    const button = Array.from(document.querySelectorAll(
                      'button[type="submit"], input[type="submit"], button:not([type])'
                    )).find(candidate => candidate.form === form);
                    if (!button || button.disabled || button.getAttribute('aria-disabled') === 'true') return false;
                    button.click();
                    return true;
                    """,
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                if value as? Bool == true { return true }
            } catch {
                // React may still be enabling the submit button after the input event.
            }
            if attempt + 1 < max(1, attempts) {
                do {
                    try await Task.sleep(for: retryDelay)
                } catch {
                    return false
                }
            }
        }
        return false
    }
}
