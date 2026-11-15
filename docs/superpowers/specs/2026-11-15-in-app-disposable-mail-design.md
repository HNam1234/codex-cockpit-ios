# In-App Disposable Mail Design

## Intent

Add a free disposable-mail inbox to Codex Cockpit iOS for occasional verification mail. A user can create roughly 7-8 addresses per month, keep each mailbox in the app for a selected 30 or 60 days, read messages and copy verification codes without leaving the app, and optionally map one active mailbox to a Codex account and its existing WebKit profile.

## Goals

- Create a Mail.tm address directly from the iPhone without a VPS, API key, or paid service.
- Read inboxes and message bodies inside the app, with pull-to-refresh and a lightweight foreground refresh.
- Detect common 4-8 character verification codes and expose an explicit **Copy code** action; never submit codes automatically.
- Let the user choose a local 30- or 60-day lifetime, defaulting to 60 days.
- Show the remaining lifetime, unread count, last refresh time, and linked Codex account/WebKit.
- Allow manual delete, unlink, or replacement of a mailbox at any time.
- Store mailbox credentials only in the iOS Keychain and keep the UI bilingual in Vietnamese and English.
- Preserve the current account identity, quota, OAuth, device-code, and isolated WebKit behavior.

## Non-goals

- Do not automate account registration, bulk mailbox creation, verification-code submission, or any provider-limit bypass.
- Do not support sending email.
- Do not claim that Mail.tm guarantees an address will remain alive or accepted for 30 or 60 days. Those values are app-managed retention targets, not a provider SLA.
- Do not promise real-time push notifications. With no backend, iOS background polling is not reliable enough for that promise.
- Do not load remote HTML resources, tracking pixels, or inline scripts from messages.
- Do not download attachments in the first release; message detail may show attachment names and sizes only.

## Constraints

- iOS 17+, SwiftUI, Foundation, and Security; no new third-party dependency.
- The phone communicates only with the exact HTTPS API host `api.mail.tm` for disposable mail.
- Mail.tm is a public temporary-mail service. Mail content and mailbox availability remain subject to that provider.
- Mail.tm requires visible attribution and enforces request-rate limits. The app must identify the provider and stay well below the documented limit.
- Cleanup at the selected expiry time cannot be guaranteed while the app is closed. Expired mailboxes are deleted on the next foreground activation, with retry state retained if the provider is unavailable.

## Approaches

1. **Mail.tm direct API — chosen.** It is free, needs no API key or separate account, and exposes account, token, inbox, message, and delete endpoints. The tradeoff is provider-controlled availability and no documented 30/60-day lifetime guarantee.
2. **Cloudflare Email Routing plus Worker/D1.** This offers controlled retention and a stable custom domain without a VPS, but it needs a domain and therefore is not guaranteed to be free for this user. It remains the future upgrade path if reliability becomes more important than zero cost.
3. **Alias forwarding or another public temp-mail provider.** Rejected for the first version because forwarding does not provide a self-contained inbox, while less documented public services increase lock-in and reliability risk.

## Architecture

`DisposableMailAPIClient` isolates the provider API behind a small protocol so the app can use deterministic stubs in tests and swap providers later. The production client performs only these flows:

1. Fetch available domains.
2. Generate a random local part and a cryptographically random password on device.
3. Create the provider account and obtain a bearer token.
4. List and read messages; mark a message seen when opened.
5. Re-authenticate with the stored address and password if a token is rejected.
6. Delete the provider account when the user deletes it or when its app-managed lifetime expires.

Requests use an exact-host allowlist, HTTPS, bounded timeouts, and a serialized rate limiter. HTTP 429 responses use exponential backoff with jitter. No password, token, message body, authorization header, or complete provider response is written to logs.

The UI talks to a `DisposableMailStore` on the main actor. The store owns cached metadata, mailbox-to-account mapping, foreground refresh scheduling, expiry evaluation, and deletion retries. Provider credentials are accessed through a `DisposableMailCredentialVault` backed by the Keychain with a `ThisDeviceOnly` accessibility class.

## Data Model

### DisposableMailbox

- Local UUID and provider account ID.
- Address, created time, selected lifetime (`30` or `60` days), and local expiry time.
- Optional linked Codex account ID. At most one active disposable mailbox can be linked to a given Codex account.
- State: `active`, `expired`, `pendingDeletion`, `providerUnavailable`, or `deleted`.
- Unread count, last successful refresh, and last provider error category.
- Credentials stored separately in Keychain: address, password, and current bearer token.

### DisposableMessage

- Provider message ID and owning mailbox ID.
- Sender name/address, subject, preview, plain-text body, received time, seen state, and attachment metadata.
- Extracted verification-code candidates are derived locally and need not be persisted separately.

Mailbox metadata and a small read-only message cache remain local so an inbox can still be viewed offline. Deleting local app data removes cached mail and Keychain entries.

## Account and WebKit Mapping

- A mailbox can be created unlinked or linked to one existing Codex account.
- Account selection shows the detected account email, falling back to the existing display name only when no email is known.
- Linking a mailbox does not share cookies or credentials with WebKit. The association is only local UI metadata.
- The account detail screen links to its mailbox, and the Mail tab shows the mapped account and WebKit label.
- Replacing an account's current mailbox requires an explicit choice to delete the old mailbox or keep it unlinked.
- Deleting a Codex account does not silently delete its mailbox; the app asks whether to delete or keep the mailbox unlinked.

## UI

Add a fourth bottom tab named **Mail** / **Thư**.

The Mail tab shows compact mailbox cards with address, linked account, remaining days, unread badge, last refresh, and actions for copy, open, unlink, and delete. A `+` sheet lets the user choose 30 or 60 days and optionally select an account before creation. The default is 60 days.

Opening a card shows a native inbox list. Pull-to-refresh updates it immediately. While the Mail tab is visible, the app may refresh no more than once per minute; returning to the foreground refreshes stale mailboxes. Offline mode keeps cached messages readable and clearly labels them as cached.

Message detail displays safe plain text, sender, timestamp, subject, and attachment metadata. Likely verification codes appear as tappable pills with **Copy code**. Links require an explicit user tap and a confirmation before leaving the app. Remote images and raw HTML are not rendered.

The account detail screen adds a **Temporary mail** / **Mail tạm** card with address, remaining lifetime, unread count, and an **Open inbox** action. Settings includes provider attribution, privacy explanation, and a control to clear local disposable-mail data.

## Lifetime and Deletion

- The selected lifetime starts when provider account creation succeeds.
- The app schedules local reminders seven days and one day before expiry when notification permission is available.
- At local expiry, the mailbox becomes read-only and hidden from normal active lists immediately.
- On the next app activation, the store requests provider deletion. If deletion succeeds or the provider reports the account missing, the app removes credentials and cached content.
- If deletion fails because of network or provider availability, the mailbox remains hidden as `pendingDeletion`, its credentials remain protected in Keychain, and deletion retries on later activations.
- The user can choose **Forget locally** after a clear warning when repeated provider deletion cannot be confirmed.
- If Mail.tm removes a mailbox before its selected local expiry, the app marks it unavailable, preserves the mapping suggestion, and offers one-tap creation of a replacement address.

The UI must state plainly that 30/60 days is the app's intended retention period and not a Mail.tm guarantee.

## Verification-Code Extraction

Extraction runs locally over the subject and plain-text body. It prioritizes 4-8 digit or alphanumeric tokens near labels such as `code`, `OTP`, `verification`, `mã`, or `xác minh`, then falls back to isolated numeric tokens. Dates, prices, phone numbers, and long identifiers receive a lower score. The UI can show more than one candidate rather than guessing silently.

Copying is always an explicit user action. The app never opens an account page, fills a code, or submits a form on the user's behalf.

## Privacy and Security

- Mailbox password and token live in Keychain using a device-only accessibility class.
- No disposable-mail credential or message content is sent to a VPS, analytics service, or the app's TIBO integration.
- No credential or message content appears in logs, crash breadcrumbs, notifications, or UI previews by default.
- The app connects only to `https://api.mail.tm`; redirects to another host fail closed.
- Message HTML is converted to inert text. Remote images, scripts, CSS, and tracking resources are never loaded.
- The privacy screen explains that Mail.tm necessarily processes and stores received messages as the external provider.
- Provider attribution is visible in the Mail tab and Settings, consistent with Mail.tm's published terms.

## Failure Behavior

- Domain-list failure leaves creation disabled with retry guidance and does not lose existing cached inboxes.
- Address conflict automatically retries with a new random local part a small bounded number of times.
- Authentication failure first attempts one token refresh; repeated failure marks the mailbox unavailable without deleting local evidence.
- Rate limiting pauses refreshes and surfaces the next retry time instead of issuing repeated requests.
- Message-list or message-detail failure preserves the last known cache and distinguishes offline, provider, authentication, and missing-account states.
- Partial creation is cleaned up when possible. The app never shows a mailbox as ready until account creation, token acquisition, and Keychain persistence all succeed.

## Validation

- API-client tests cover domains, account creation, token acquisition/refresh, inbox list, message detail, mark-seen, deletion, redirects, timeouts, 401, 404, and 429 backoff.
- Store tests cover 30/60-day expiry, reminders, foreground cleanup, pending deletion, early provider removal, replacement, and one-mailbox-per-account mapping.
- Credential-vault tests use an injectable fake and verify no secret appears in the metadata store or logs.
- Verification-code tests cover Vietnamese and English labels, multiple candidates, false positives, and alphanumeric codes.
- UI tests and previews cover empty, creating, active, offline-cache, unavailable, expired, and pending-deletion states in Vietnamese and English.
- Regression tests preserve account identity, quota refresh, direct OAuth, device-code flow, and isolated WebKit mapping.
- CI must pass unit/UI tests, simulator build, archive, and unsigned IPA packaging before release.

## Rollout

- Target version: `v1.9.0-personal`, build `23`.
- Ship Mail as an additive fourth tab; existing accounts and WebKit mappings require no migration beyond an empty mailbox store.
- Keep provider failure isolated so Overview, WebKit, OAuth, quota refresh, and TIBO continue working when Mail.tm is down.
- Release through the existing private GitHub workflow after rendered UI review on both supported languages and CI verification.
- A future release can add a custom-domain Cloudflare provider behind the same client protocol without changing the Mail UI or stored mapping model.
