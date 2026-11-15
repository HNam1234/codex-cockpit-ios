# VPS OAuth Quota Sync Design

## Intent

Make direct OAuth in an account's mapped iOS WebKit finish the same way as the older VPS-managed accounts: the selected VPS slot becomes the credential owner, Codex app-server reads its quota, and the app immediately renders that quota without opening the usage website.

## Goals

- Import the signed-in WebKit account into the selected VPS account slot after direct OAuth.
- Return a live Codex app-server snapshot so email, plan, subscription expiry, and quota update immediately in the native UI.
- On the first launch after upgrading, sync an existing Keychain registration only when its mapped VPS slot still needs login or has no quota.
- Create future accounts on the VPS first, then assign one dedicated WebKit, so add/delete and quota behavior match existing accounts.
- Preserve WebKit isolation, device-code fallback, pull-to-refresh, Vietnamese/English UI, and current account mappings.
- Roll back the old VPS `auth.json` byte-for-byte if Codex rejects the imported credentials.

## Non-goals

- Do not upload WebKit cookies or browser storage.
- Do not expose OAuth tokens in logs, errors, app UI, source control, or release artifacts.
- Do not make the iPhone refresh tokens after the VPS accepts them; the VPS owns subsequent refreshes.
- Do not modify a different account slot based only on a detected email; the explicit account-to-WebKit mapping remains authoritative.

## Constraints

- iOS 17+, SwiftUI/Foundation/WebKit only; no new app dependency.
- Keep the existing authenticated Tailscale HTTPS backend and app-token boundary.
- Accept only ChatGPT OAuth credentials whose ID/access token claims agree on issuer, client, subject, and ChatGPT account ID.
- The endpoint must be transactional: write, ask Codex app-server for a real snapshot, then keep or restore.
- The current five VPS accounts and their quota state must remain intact unless that exact mapped slot is successfully reauthorized.

## Approaches

1. **Transactional token import into the mapped VPS slot — chosen.** It reuses the exact Codex app-server/quota path used by existing accounts and makes the native UI authoritative. HTTPS protects transfer, Keychain protects the device copy, and rollback protects the old slot.
2. **Read usage from ChatGPT WebKit only.** Rejected because the web session and Codex OAuth credentials are independent and the usage page is not a stable native quota API.
3. **Keep direct OAuth device-only and show a connected badge.** Rejected because it reproduces the current bug: identity appears connected while VPS quota remains unavailable.

## Flow

1. The user starts direct OAuth from a VPS-backed account and its mapped WebKit.
2. iOS exchanges and verifies the OAuth response, saves it in this-device-only Keychain storage, then posts the credentials for that explicit account ID to the VPS.
3. The VPS validates token shape and cross-token identity, atomically installs Codex `auth.json`, and asks Codex app-server for a snapshot.
4. Success keeps the new credentials, persists the fresh snapshot, and returns it to iOS. Failure restores the previous credentials and returns an actionable error with no token content.
5. iOS replaces the account snapshot, so email, plan, days remaining, and 5-hour/weekly quota render immediately.
6. On upgrade, a saved registration is imported once only for a mapped remote slot that is unauthenticated or lacks quota.

## Validation

- Python unit tests cover matched tokens, identity mismatch, malformed input, and transactional rollback.
- Swift tests cover sending a registration through the store and replacing the remote snapshot.
- Static verification, full macOS XCTest/XCUITest, an unsigned device build, live VPS health, and a real account import/quota refresh are required before release.

