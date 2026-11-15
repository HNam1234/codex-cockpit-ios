# In-App Disposable Mail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a free, secure Mail.tm inbox to Codex Cockpit iOS with 30/60-day app-managed retention, local OTP extraction, and optional one-to-one Codex account/WebKit mapping.

**Architecture:** Keep provider transport, Keychain secrets, disk cache/lifecycle, and SwiftUI presentation behind focused protocols. A main-actor `DisposableMailStore` coordinates those pieces and is injected once from `RootView`; Mail.tm failure remains isolated from the existing Cockpit, OAuth, quota, and WebKit flows.

**Tech Stack:** Swift 5, SwiftUI, Foundation `URLSession`, Security Keychain, UserNotifications, XCTest/XCUITest, XcodeGen, GitHub Actions macOS runner.

**Spec:** `docs/superpowers/specs/2026-11-15-in-app-disposable-mail-design.md`

## Global Constraints

- iOS 17+ only; no new third-party dependency and no VPS.
- Connect only to exact HTTPS host `api.mail.tm`; reject cross-host redirects.
- Default to 60 days and allow exactly 30 or 60 days as app-managed retention targets, never as a provider guarantee.
- Keep password/token in Keychain with a `ThisDeviceOnly` accessibility class; never log or persist secrets in metadata/cache.
- Do not render remote HTML, images, scripts, CSS, or tracking resources and do not download attachments in this release.
- Never submit OTPs or automate registrations; copying a candidate requires an explicit user action.
- Add Vietnamese and English copy for every new user-visible string.
- Preserve all account identity, quota refresh, OAuth, device-code, TIBO, and persistent WebKit behavior.
- Push implementation and release artifacts only to the private `personal` repository; leave public `origin/main` unchanged.

## Review Focus

- A malicious redirect or response URL outside exact `https://api.mail.tm` must be rejected by Task 2 transport tests.
- A partial create where the provider account exists but token or Keychain storage fails must not surface a ready mailbox and must attempt cleanup in Task 4 tests.
- An expired mailbox whose provider deletion is offline must become hidden/read-only while retaining a safe retry tombstone in Task 4 tests.
- Duplicate account linking and account deletion must never silently delete or orphan a mailbox; Task 4 and Task 5 tests pin replacement/unlink behavior.
- Large or hostile HTML-only messages, false-positive number strings, offline cache, narrow screens, and both languages must remain safe and usable in Task 1 and Task 5 tests.

---

### Task 1: Mailbox models, lifetime rules, and verification-code extraction

**Files:**
- Create: `CodexCockpit/Models/DisposableMail.swift`
- Create: `CodexCockpit/Services/VerificationCodeExtractor.swift`
- Create: `CodexCockpitTests/DisposableMailModelTests.swift`
- Create: `CodexCockpitTests/VerificationCodeExtractorTests.swift`

**Interfaces:**
- Produces: `MailboxLifetime: Int, Codable, CaseIterable` with only `.thirtyDays` and `.sixtyDays`, `default == .sixtyDays`, and `expiry(from:)`.
- Produces: `DisposableMailboxState: String, Codable` with `.active`, `.expired`, `.pendingDeletion`, `.providerUnavailable`, and `.deleted`.
- Produces: `DisposableMailbox: Identifiable, Codable, Hashable` containing local/provider IDs, address, dates, linked account, state, unread count, refresh time, and safe error category only.
- Produces: `DisposableMessage: Identifiable, Codable, Hashable` containing provider ID, mailbox ID, sender, subject, intro/plain text, date, seen state, and attachment metadata only.
- Produces: `MailTextSanitizer.plainText(text: String?, html: [String]) -> String` with bounded inert output for text-only and HTML-only messages.
- Produces: `VerificationCodeExtractor.codes(subject: String, body: String) -> [String]` ordered by confidence and deduplicated.

- [ ] **Step 1: Write failing lifetime/model tests**

Assert that default retention is 60 days, both exact expiry dates use calendar-day addition, decoding rejects unsupported lifetime values, active remaining days never go below zero, and no credential fields exist in encoded mailbox/message JSON.

- [ ] **Step 2: Run the private macOS test job and verify RED**

Expected: compile failure because the disposable-mail types do not exist.

- [ ] **Step 3: Implement the models and pure lifetime helpers**

Keep all dates as `Date`, use injected `Calendar`/`now` in helpers, and expose localized countdown data rather than localized strings from model storage.

- [ ] **Step 4: Write failing verification-code tests**

Require ranked extraction for English `verification code`, Vietnamese `mã xác minh`, 4-8 digit and alphanumeric codes, duplicate removal, multiple candidates, bounded plain-text preservation, safe HTML-only fallback, entity decoding, removal of scripts/styles/tags, and rejection/down-ranking of dates, prices, phone numbers, and long identifiers.

- [ ] **Step 5: Implement the minimal local extractor**

Sanitize provider content into bounded inert text, score isolated candidates higher when near a supported label, cap input length and result count, and never execute or render HTML.

- [ ] **Step 6: Run focused and full tests GREEN**

Expected: model and extraction tests pass with no network or Keychain access.

- [ ] **Step 7: Commit**

```bash
git add CodexCockpit/Models/DisposableMail.swift CodexCockpit/Services/VerificationCodeExtractor.swift CodexCockpitTests/DisposableMailModelTests.swift CodexCockpitTests/VerificationCodeExtractorTests.swift
git commit -m "feat: add disposable mail models and OTP extraction"
```

### Task 2: Exact-host Mail.tm API client and backoff

**Files:**
- Create: `CodexCockpit/Services/MailTMClient.swift`
- Create: `CodexCockpitTests/MailTMClientTests.swift`

**Interfaces:**
- Consumes: `DisposableMessage` and attachment metadata from Task 1.
- Produces: `MailTMCredential: Equatable, Sendable` containing provider account ID, address, password, and token for transient/Keychain use only.
- Produces: `MailTMAccount`, `MailTMDomain`, and `MailTMPage<T>` internal DTOs that decode Hydra responses without leaking into UI code.
- Produces: `DisposableMailServing: Sendable` with async `createAccount`, `authenticate`, `listMessages`, `message`, `markSeen`, and `deleteAccount` methods.
- Produces: `MailTMClient: DisposableMailServing` initialized with injectable `URLSession`, rate clock/sleep, random address/password factory, and exact base URL fixed to `https://api.mail.tm` in production.
- Produces: `DisposableMailServiceError: Error, Equatable` with safe cases for offline, unavailable, unauthorized, missing, rate-limited retry date, malformed response, and rejected host.

- [ ] **Step 1: Write failing request/decoding tests with `URLProtocol` stubs**

Assert exact methods, paths, JSON bodies, bearer headers, Hydra list decoding, plain-text message decoding, mark-seen payload, delete handling, percent-safe message IDs, and absence of password/token in error descriptions.

- [ ] **Step 2: Run the focused test job and verify RED**

Expected: compile failure for missing client/protocol types.

- [ ] **Step 3: Implement provider DTOs and endpoint methods**

Use `URLSessionConfiguration.ephemeral`, bounded request/resource timeouts, `Accept: application/json`, and `Content-Type: application/json` only where needed. Accept success status codes per endpoint and map all public errors to safe categories.

- [ ] **Step 4: Write failing transport-safety and backoff tests**

Reject non-HTTPS or non-exact hosts, cancel redirects away from `api.mail.tm`, serialize requests to at most four per second, honor numeric `Retry-After`, and use bounded jittered 1/2/4-second retries for 429 or transient 5xx responses.

- [ ] **Step 5: Implement exact-host delegate, limiter, and retry policy**

Inject sleep/random jitter for deterministic tests; retry idempotent reads automatically and let create/delete retry only when response semantics prove the request was not committed.

- [ ] **Step 6: Run focused and full tests GREEN**

Expected: all client tests pass without contacting the real Mail.tm service.

- [ ] **Step 7: Commit**

```bash
git add CodexCockpit/Services/MailTMClient.swift CodexCockpitTests/MailTMClientTests.swift
git commit -m "feat: add secure Mail.tm API client"
```

### Task 3: Keychain vault, atomic local cache, and reminder scheduler

**Files:**
- Create: `CodexCockpit/Services/DisposableMailCredentialVault.swift`
- Create: `CodexCockpit/Services/DisposableMailPersistence.swift`
- Create: `CodexCockpit/Services/DisposableMailReminderScheduler.swift`
- Create: `CodexCockpitTests/DisposableMailStorageTests.swift`

**Interfaces:**
- Consumes: `MailTMCredential`, `DisposableMailbox`, and `DisposableMessage` from Tasks 1-2.
- Produces: `DisposableMailCredentialVaultProtocol` with `save(_:mailboxID:)`, `credential(mailboxID:)`, and `delete(mailboxID:)`.
- Produces: `DisposableMailCredentialVault` using generic-password Keychain records, per-mailbox account keys, and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Produces: `DisposableMailPersisting` with atomic `load/save` for `DisposableMailSnapshot(mailboxes:messagesByMailbox:)` in Application Support.
- Produces: `DisposableMailReminderScheduling` with `schedule(mailbox:)` and `cancel(mailboxID:)`; production schedules local notifications seven and one day before expiry when still in the future.

- [ ] **Step 1: Write failing vault/persistence tests using fakes and a temporary directory**

Assert credential replacement, delete, atomic snapshot round-trip, corrupt-cache recovery to an empty snapshot, file protection selection, and that serialized cache never contains known password/token fixtures.

- [ ] **Step 2: Run focused tests and verify RED**

Expected: compile failure for missing storage interfaces.

- [ ] **Step 3: Implement the Keychain vault and atomic JSON persistence**

Encode the credential only inside the Keychain value, use device-only accessibility, write cache to a temporary sibling then replace atomically, and cap cached body/message counts per mailbox.

- [ ] **Step 4: Write failing reminder tests with an injected notification center adapter**

Assert stable identifiers, seven-day/one-day dates, no past reminders, replacement on lifetime change, cancellation on delete, and no message content in notification bodies.

- [ ] **Step 5: Implement the reminder scheduler**

Schedule only calendar triggers for mailbox expiry warnings; permission denial must not block mailbox creation.

- [ ] **Step 6: Run focused and full tests GREEN**

Expected: storage/reminder tests pass and existing TIBO notification tests remain green.

- [ ] **Step 7: Commit**

```bash
git add CodexCockpit/Services/DisposableMailCredentialVault.swift CodexCockpit/Services/DisposableMailPersistence.swift CodexCockpit/Services/DisposableMailReminderScheduler.swift CodexCockpitTests/DisposableMailStorageTests.swift
git commit -m "feat: persist disposable mail securely"
```

### Task 4: Mailbox store, mapping, refresh, and expiry cleanup

**Files:**
- Create: `CodexCockpit/Services/DisposableMailStore.swift`
- Create: `CodexCockpitTests/DisposableMailStoreTests.swift`

**Interfaces:**
- Consumes: provider, vault, persistence, reminders, models, and extractor from Tasks 1-3.
- Produces: `@MainActor final class DisposableMailStore: ObservableObject` with published `mailboxes`, `messagesByMailbox`, `busyMailboxIDs`, and safe `errorMessage`.
- Produces: async `create(lifetime:linkedAccountID:)`, `refresh(mailboxID:force:)`, `loadMessage(mailboxID:messageID:)`, `delete(mailboxID:)`, `retryPendingDeletions()`, and `handleForeground(validAccountIDs:)`.
- Produces: sync `link(mailboxID:toAccountID:replacement:)`, `unlinkAccount(_:)`, `mailbox(linkedTo:)`, and `forgetLocally(mailboxID:)`.
- Produces: replacement policy `.deleteExisting` or `.keepExistingUnlinked`; no call silently overwrites a mapping.

- [ ] **Step 1: Write failing create/refresh tests with provider/vault/storage fakes**

Assert successful 60-day default creation, optional mapping, unread calculation, one-minute stale threshold, explicit force refresh, token refresh after one 401, mark-seen behavior, offline cache retention, and no UI-ready mailbox before provider + token + Keychain + persistence all succeed.

- [ ] **Step 2: Add failing partial-create and provider-error tests**

Assert cleanup after token or vault failure, bounded conflict retry, 404/disabled to `providerUnavailable`, 429 retry date exposure, and no secret-bearing errors.

- [ ] **Step 3: Implement create, refresh, message load, and safe recovery**

Generate provider credentials transiently, persist them before publishing the mailbox, re-authenticate once on 401, update cache atomically, and preserve cached content for offline/unavailable states.

- [ ] **Step 4: Write failing mapping/lifecycle/deletion tests**

Cover one active mailbox per account, explicit replacement choices, account deletion unlink without mailbox deletion, 30/60-day expiry, hidden/read-only expired state, foreground deletion success, offline `pendingDeletion`, retry success, provider 404 as confirmed deletion, reminder cancellation, and explicit local forget.

- [ ] **Step 5: Implement mapping, expiry, tombstones, and foreground refresh**

Evaluate expiry before refresh, hide expired/pending mailboxes from active lists, retain credentials until provider deletion succeeds, refresh stale active mailboxes no more than once per minute, and make all destructive transitions idempotent.

- [ ] **Step 6: Run focused and full tests GREEN**

Expected: store tests pass deterministically using injected clock and no real provider calls.

- [ ] **Step 7: Commit**

```bash
git add CodexCockpit/Services/DisposableMailStore.swift CodexCockpitTests/DisposableMailStoreTests.swift
git commit -m "feat: manage disposable mailbox lifecycle"
```

### Task 5: Mail tab, native inbox/message UI, account integration, and localization

**Files:**
- Create: `CodexCockpit/Views/MailView.swift`
- Create: `CodexCockpit/Views/MailboxDetailView.swift`
- Create: `CodexCockpit/Views/DisposableMessageView.swift`
- Modify: `CodexCockpit/Views/RootView.swift`
- Modify: `CodexCockpit/Models/AccountProfile.swift`
- Modify: `CodexCockpit/Views/ProfileDetailView.swift`
- Modify: `CodexCockpit/Views/AccountsView.swift`
- Modify: `CodexCockpit/Views/SettingsView.swift`
- Modify: `CodexCockpit/en.lproj/Localizable.strings`
- Modify: `CodexCockpit/vi.lproj/Localizable.strings`
- Modify: `CodexCockpitTests/LocalizationTests.swift`
- Modify: `CodexCockpitUITests/LaunchTests.swift`

**Interfaces:**
- Consumes: the complete `DisposableMailStore` API from Task 4 and existing `CockpitStore`/`ProfileMappingStore` identity labels.
- Produces: `AppTab.mail`, a fourth **Mail** / **Thư** tab, mailbox creation/link sheet, mailbox/inbox/message views, account-detail mail card, and Settings privacy/attribution/clear-data controls.
- Produces: deterministic `PREVIEW_TAB=mail` and `PREVIEW_MAIL_SAMPLE=1` launch state that never contacts Mail.tm.

- [ ] **Step 1: Write failing localization and shell UI tests**

Require four Vietnamese and English tabs, an empty Mail state, `mail-create` sheet with 30/60 selection defaulted to 60, optional account picker using detected email, visible Mail.tm attribution, and no network call in `UITEST_MODE`.

- [ ] **Step 2: Run the private macOS workflow and verify RED**

Expected: localization assertions and Mail-tab element lookups fail.

- [ ] **Step 3: Inject the store and implement the Mail shell/create flow**

Create one `@StateObject` in `RootView`, pass it through `environmentObject`, add `AppTab.mail`, load/cleanup on active scene phase, and build smooth empty/loading/error/card states with pull-to-refresh and snappy bounded animations.

- [ ] **Step 4: Write failing inbox/message UI tests against sample data**

Require remaining days, unread badge, linked account/WebKit label, cached/offline indicator, safe plain text, sender/date/subject, multiple OTP pills, explicit copy action, attachment metadata without download, and delete/unlink confirmation.

- [ ] **Step 5: Implement mailbox, inbox, and safe message views**

Use native `List`/lazy containers, inert text only, redacted notification/UI previews, explicit link confirmation, `.refreshable`, accessible labels, Dynamic Type, and no timer faster than one minute while visible.

- [ ] **Step 6: Integrate account detail, account deletion, and Settings**

Show the mapped mailbox card in account detail. On Codex account deletion, explicitly offer keep-unlinked or delete-mailbox behavior before completing the existing WebKit/account removal. When a provider mailbox disappears early, show a one-tap replacement action that preserves its account-link suggestion. Add provider/privacy text, clear-local-data warning, and Mail.tm attribution in Settings.

- [ ] **Step 7: Add both-language copy and preview launch data**

Localize every new label/error/countdown, seed an in-memory mailbox/message only under preview/UI-test environment, and add Vietnamese/English Mail list and message-detail capture routes.

- [ ] **Step 8: Run focused and full tests GREEN**

Expected: all localization/unit/UI tests pass; existing account, OAuth, device-code, quota, TIBO, and WebKit tests remain green.

- [ ] **Step 9: Commit**

```bash
git add CodexCockpit/Views/MailView.swift CodexCockpit/Views/MailboxDetailView.swift CodexCockpit/Views/DisposableMessageView.swift CodexCockpit/Views/RootView.swift CodexCockpit/Models/AccountProfile.swift CodexCockpit/Views/ProfileDetailView.swift CodexCockpit/Views/AccountsView.swift CodexCockpit/Views/SettingsView.swift CodexCockpit/en.lproj/Localizable.strings CodexCockpit/vi.lproj/Localizable.strings CodexCockpitTests/LocalizationTests.swift CodexCockpitUITests/LaunchTests.swift
git commit -m "feat: add disposable mail inbox UI"
```

### Task 6: Static hardening, documentation, previews, version, and private release

**Files:**
- Modify: `scripts/verify_project.py`
- Modify: `README.md`
- Modify: `.github/workflows/build-unsigned-ipa.yml`
- Modify: `project.yml`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: security assertions, bilingual Mail preview artifacts, version `1.9.0` build `23`, and a private unsigned IPA release.

- [ ] **Step 1: Extend static verification**

Assert exact Mail.tm host, device-only Keychain accessibility, no remote HTML renderer, Mail pull-to-refresh, no new committed secrets, no provider credential keys in persisted model source, and presence of both-language Mail strings.

- [ ] **Step 2: Document behavior and honest limitations**

Explain creation, account mapping, inbox/OTP, local 30/60-day retention, next-foreground deletion, provider early-removal risk, offline cache, no push guarantee, no outgoing mail, privacy boundary, and Mail.tm attribution.

- [ ] **Step 3: Extend CI previews and bump version**

Capture Vietnamese/English Mail list and message detail using deterministic sample data. Set `MARKETING_VERSION=1.9.0` and `CURRENT_PROJECT_VERSION=23` exactly once.

- [ ] **Step 4: Run local static checks**

Run:

```powershell
python scripts\verify_project.py
git diff --check
git status --short
```

Expected: static verification passes, no whitespace errors, and only intended files are changed.

- [ ] **Step 5: Run final private CI and inspect previews**

Push the feature branch to `personal`, dispatch `Build unsigned IPA`, verify unit/UI tests, unsigned device build, IPA packaging, and artifact upload, then visually inspect Mail list/detail plus existing Overview/WebKit/Settings in both languages for clipping, stale data, unsafe message rendering, or regressions.

- [ ] **Step 6: Perform a bounded live Mail.tm smoke test**

On a disposable test mailbox only, create one address, fetch its empty inbox, and delete it. Do not use a real personal account or leave the smoke mailbox active. Record only status/result, never address/password/token.

- [ ] **Step 7: Commit release preparation**

```bash
git add scripts/verify_project.py README.md .github/workflows/build-unsigned-ipa.yml project.yml
git commit -m "release: prepare disposable mail 1.9.0"
```

- [ ] **Step 8: Create the private release and preserve public main**

Publish `v1.9.0-personal` with the unsigned IPA and bilingual Mail previews, record the IPA SHA-256, verify the release asset is downloadable, and verify `origin/main` remains at its pre-feature commit.
