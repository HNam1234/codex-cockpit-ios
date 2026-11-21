import Foundation
import WebKit

enum AutofillStatus: Equatable {
    case idle
    case waiting
    case filled
    case notFound
}

enum DeviceCodeAutofill {
    static let messageHandlerName = "cockpitAutofill"

    static let userScript = WKUserScript(
        source: source,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true,
        in: .defaultClient
    )

    static func supports(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.host?.lowercased() == AppURLs.deviceLogin.host?.lowercased()
            && url.path.hasPrefix(AppURLs.deviceLogin.path)
    }

    @MainActor
    static func fill(
        code: String,
        in webView: WKWebView,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard supports(webView.url), let literal = jsonLiteral(code) else {
            completion?(false)
            return
        }

        let autoSubmit = UserDefaults.standard.bool(forKey: "CodexCockpit.autoSubmitCode.v1")
        let script = """
        (() => {
          if (typeof window.__cockpitFillCode !== 'function') return false;
          window.__cockpitFillCode(\(literal), \(autoSubmit ? "true" : "false"));
          return true;
        })();
        """
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
            let started: Bool
            switch result {
            case .success(let value):
                started = (value as? Bool) == true
            case .failure:
                started = false
            }
            DispatchQueue.main.async { completion?(started) }
        }
    }

    private static func jsonLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static let source = #"""
    (() => {
      'use strict';

      const allowedPage = () =>
        location.host.toLowerCase() === 'auth.openai.com' &&
        location.pathname.startsWith('/codex/device');

      const post = (type) => {
        try {
          window.webkit.messageHandlers.cockpitAutofill.postMessage({ type });
        } catch (_) {}
      };

      const visible = (element) => {
        if (!(element instanceof HTMLInputElement) || element.disabled) return false;
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== 'none' && style.visibility !== 'hidden' &&
          Number(style.opacity || '1') !== 0 && rect.width > 0 && rect.height > 0;
      };

      const setValue = (input, value) => {
        const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        if (!descriptor || typeof descriptor.set !== 'function') return false;
        descriptor.set.call(input, value);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        input.focus();
        return true;
      };

      const singleInput = () => {
        const preferred = [
          ...document.querySelectorAll('input[autocomplete="one-time-code"]'),
          ...document.querySelectorAll('input[name*="code" i], input[id*="code" i]')
        ].filter(visible);
        if (preferred.length > 0) return preferred[0];

        const formInputs = [...document.querySelectorAll('form input[inputmode="text"]')].filter(visible);
        return formInputs.length === 1 ? formInputs[0] : null;
      };

      const characterInputs = () => {
        const inputs = [...document.querySelectorAll('input[maxlength="1"]')].filter(visible);
        return inputs.length >= 6 ? inputs : [];
      };

      const submitContainingForm = (input) => {
        const form = input && input.closest('form');
        if (!form) return;
        if (typeof form.requestSubmit === 'function') {
          form.requestSubmit();
          return;
        }
        const button = form.querySelector('button[type="submit"], input[type="submit"]');
        if (button) button.click();
      };

      window.__cockpitFillCode = (rawCode, autoSubmit = false) => {
        if (!allowedPage() || typeof rawCode !== 'string') return false;

        const previous = window.__cockpitAutofillPending;
        if (previous) {
          if (previous.observer) previous.observer.disconnect();
          if (previous.timer) clearTimeout(previous.timer);
        }

        const pending = { observer: null, timer: null, completed: false };
        window.__cockpitAutofillPending = pending;
        const code = rawCode.toUpperCase();
        const compactCode = code.replace(/-/g, '');

        const attempt = () => {
          if (pending.completed || !allowedPage()) return false;

          const cells = characterInputs();
          let anchor = null;
          let filled = false;
          if (cells.length >= 6) {
            if (cells.length < compactCode.length) return false;
            for (let index = 0; index < compactCode.length; index += 1) {
              filled = setValue(cells[index], compactCode[index]) || filled;
            }
            anchor = cells[0];
          } else {
            anchor = singleInput();
            if (anchor) filled = setValue(anchor, code);
          }

          if (!filled) return false;
          pending.completed = true;
          if (pending.observer) pending.observer.disconnect();
          if (pending.timer) clearTimeout(pending.timer);
          post('codeFilled');
          if (autoSubmit) submitContainingForm(anchor);
          return true;
        };

        if (attempt()) return true;
        if (!document.body) {
          post('codeNotFound');
          return false;
        }

        pending.observer = new MutationObserver(attempt);
        pending.observer.observe(document.body, { childList: true, subtree: true, attributes: true });
        pending.timer = setTimeout(() => {
          if (pending.completed) return;
          pending.completed = true;
          if (pending.observer) pending.observer.disconnect();
          post('codeNotFound');
        }, 8000);
        return true;
      };
    })();
    """#
}

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
