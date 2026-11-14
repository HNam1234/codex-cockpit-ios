# Account Identity Sync and TIBO Alerts Design

## Intent

Keep each Codex account visibly tied to the ChatGPT session that is actually signed in inside its isolated WebKit profile, and make TIBO signals easier to understand and harder to miss.

## Goals

- Read only the signed-in ChatGPT user's name/email from inside the local `WKWebView`; never export cookies or tokens.
- Persist the last confirmed identity per WebKit profile so account names remain useful while quota refresh is failing.
- Automatically correct a mapping only when the WebKit email uniquely matches one VPS account email.
- Preserve manual mapping when only a name is available or a match is ambiguous.
- Reconcile cached identities again whenever fresh account data arrives.
- Refresh while the app is active using the server-provided polling interval and refresh immediately on foreground entry.
- Improve the TIBO card with a clear state, freshness, source link, and probability context.
- Offer opt-in local alerts for fresh `likely` and `yes` signals, with deduplication.

## Non-goals

- No cookie, session token, or WebKit storage is uploaded to the VPS.
- No name-only automatic remapping.
- No remote push notification service or guaranteed background execution.
- No VPS API or tracker changes.

## Constraints

- iOS 17+, SwiftUI, WebKit, and UserNotifications only; no new dependency.
- The original five `WKWebsiteDataStore` identifiers must remain unchanged.
- Existing manual swap behavior must remain available.
- Notification permission is requested only after the user enables TIBO alerts.

## Approaches

1. Scrape the visible ChatGPT sidebar. Rejected because localized labels and layout changes make it brittle, and the sidebar may not expose a unique email.
2. Ask the VPS to own profile mapping. Rejected because the VPS cannot see which account is currently signed into an isolated on-device WebKit profile.
3. Query the authenticated ChatGPT session from same-origin JavaScript inside the WebView, cache the returned display identity locally, and exact-match its normalized email against VPS accounts. Chosen because it observes the real session without exposing cookies and fails safely when identity data is unavailable.

For TIBO, the chosen approach combines a richer in-app card with optional local notifications. In-app-only alerts are too easy to miss, while remote push would require a new server and Apple push setup outside this repository.

## Behavior

- After a successful navigation on `chatgpt.com`, the WebView performs a same-origin, credentialed session lookup and returns only trimmed `name` and `email` fields to native code.
- A valid identity is stored under the WebKit profile ID. Exact email match to exactly one `AccountSnapshot` causes the existing mapping swap operation; otherwise the mapping is untouched.
- Account cards and detail headers prefer the cached identity of their mapped WebKit profile, then fall back to VPS display name, VPS email, and finally the configured account name.
- Clearing a WebKit session also clears its cached identity.
- While active, the app reloads status at a clamped 60–3600 second interval. Re-entering the foreground starts with an immediate load.
- TIBO alerts are generated only for non-stale `likely` or `yes` signals. A stable identifier made from status and post/event identity prevents repeated notifications; a `likely` signal that becomes `yes` can notify again.
