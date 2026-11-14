# Cockpit Browser OAuth Relay Design

## Intent

Let a user reauthorize a Codex account from Cockpit Tools PC through the ChatGPT session that is already signed in inside that account's mapped iOS WebKit profile. Keep Cockpit Tools PC as the OAuth client and credential owner, and keep device-code authorization as a fallback.

## Goals

- Add a browser-OAuth action beside each mapped account without removing the existing device-code action.
- Accept only a Cockpit/OpenAI authorization URL, open it in that account's persistent isolated WebKit, and reuse the signed-in ChatGPT session there.
- Intercept the loopback OAuth callback before WebKit tries to contact the iPhone's localhost.
- Validate the callback against the authorization attempt's callback host, port, path, and `state`.
- Keep the authorization URL and callback in memory only; never persist or log the authorization code, PKCE challenge, or callback URL.
- Copy the validated callback locally so the user can paste it into Cockpit Tools PC's existing manual-callback field.
- Preserve account-to-WebKit mapping, identity detection, existing quota UI, and device-code fallback.
- Support Vietnamese and English UI copy.

## Non-goals

- Do not exchange OAuth tokens on the iPhone.
- Do not read, store, export, or upload ChatGPT cookies or OpenAI tokens.
- Do not write Cockpit Tools' account database or Codex `auth.json` from iOS.
- Do not require a VPS, public relay, or new remote service.
- Do not modify or fork Cockpit Tools PC in this phase.
- Do not promise a fully automatic PC-to-iPhone transfer; the current Cockpit release exposes the needed callback submission only inside its desktop UI.

## Constraints

- iOS 17+, SwiftUI, WebKit, and Foundation only; no new dependency.
- Keep each existing `WKWebsiteDataStore` identifier unchanged.
- Cockpit Tools PC owns PKCE, `state`, callback completion, token exchange, identity verification, and credential replacement.
- The iPhone must not navigate to loopback callbacks because `localhost` and `127.0.0.1` would refer to the phone, not the PC.
- Authorization input must fail closed for malformed URLs, deceptive hosts, missing PKCE/state, unsupported redirect URIs, or callback mismatches.

## Approaches

1. **Manual callback relay through the mapped WebKit — chosen.** Cockpit PC creates its normal browser-OAuth URL. The user pastes that URL into the iOS account sheet, authorizes through the mapped WebKit, and pastes the captured callback back into Cockpit's manual-callback field. This works with the installed Cockpit release, needs no VPS, and keeps credentials on the PC.
2. **Exchange tokens on iOS and export/import them.** Rejected because it moves renewable credentials onto the phone, expands the security boundary, and still needs a transfer/import mechanism to update Cockpit PC.
3. **Automatic LAN companion.** Deferred because Cockpit's callback completion is an internal Tauri command, not an external local API. A companion or Cockpit fork could remove the final paste later, but it is a separate PC deliverable with pairing, discovery, firewall, and update concerns.

## Flow

1. In Cockpit Tools PC, the user starts **Browser authorization** for the intended account and copies the generated authorization URL.
2. In Codex Cockpit iOS, the user taps **Cockpit OAuth** on that same account and pastes the URL.
3. The app validates:
   - outer URL is HTTPS on `chatgpt.com` with path `/codex/desktop-auth`, or inner URL is HTTPS on `auth.openai.com` with path `/oauth/authorize`;
   - the inner authorize request uses authorization-code flow, PKCE S256, a non-empty challenge, and a non-empty `state`;
   - `redirect_uri` is HTTP loopback on `localhost` or `127.0.0.1`, has an explicit valid port, and path `/auth/callback`;
   - the outer hosted URL's decoded `authorize_url` passes the same inner validation.
4. The validated URL opens in the selected account's mapped persistent WebKit.
5. On navigation to the expected loopback callback, the app cancels navigation, requires non-empty `code`, and constant-time compares the returned `state` to the pending state's exact bytes.
6. The app clears the pending authorization transaction from browser state, stores the validated callback only in transient view state, copies it to the local clipboard, and shows instructions to paste it into Cockpit PC.
7. Cockpit PC validates the callback, exchanges the code with its PKCE verifier, verifies the returned account, and updates the selected Cockpit account.

## UI

- Account rows and account detail add a **Cockpit OAuth** action while retaining **Code from PC**.
- A native sheet explains the two-paste flow, accepts/pastes the PC authorization URL, and opens the mapped WebKit only after validation.
- While OAuth is pending, the browser displays a compact status bar naming the expected callback host and port.
- After capture, a result sheet shows success, auto-copies the callback, provides an explicit copy button, and reminds the user to paste it into Cockpit PC's manual callback field.
- Errors are actionable and never echo the full authorization URL, authorization code, or callback.

## Security and Failure Behavior

- Host checks compare canonical lowercased hostnames exactly; suffix or substring matches are forbidden.
- URL credentials, fragments, non-default outer schemes, absent/duplicate critical query values, and unexpected callback paths are rejected.
- Only the pending transaction can capture a callback. State mismatch leaves the transaction pending and shows an error; it never exposes or copies the mismatched callback.
- Cancelling or leaving the browser clears the pending transaction and captured callback.
- Clipboard content is user-visible and local. The app offers a clear action after the PC accepts the callback.
- Identity mismatch remains fail-closed on Cockpit PC; the iOS app also shows the mapped WebKit identity so the user can confirm the intended account before opening OAuth.

## Validation

- Unit tests cover hosted and inner URL parsing, deceptive hosts, invalid redirect URIs, missing PKCE/state, duplicate critical parameters, callback host/port/path mismatch, state mismatch, and valid capture.
- Browser-state tests prove callback capture clears the pending transaction and invalid callbacks do not.
- UI tests render the OAuth entry sheet and callback-success state in both supported languages.
- Static project verification and the full macOS CI unit/UI/build/IPA workflow must pass before release.
