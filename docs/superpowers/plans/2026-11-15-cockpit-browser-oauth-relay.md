# Cockpit Browser OAuth Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reauthorize a Cockpit Tools PC Codex account through its mapped iOS WebKit session without a VPS, while keeping Cockpit PC in control of PKCE, token exchange, identity validation, and credential storage.

**Architecture:** Add a pure URL-validation/callback-capture service, carry a validated transient OAuth attempt through the existing browser route, and intercept the loopback callback in `WKNavigationDelegate`. SwiftUI sheets start the two-paste flow and return the validated callback to Cockpit PC; device code remains available as a fallback.

**Tech Stack:** Swift 5, SwiftUI, WebKit, Foundation `URLComponents`, XCTest/XCUITest, XcodeGen, GitHub Actions macOS runner.

**Spec:** `docs/superpowers/specs/2026-11-15-cockpit-browser-oauth-relay-design.md`

## Global Constraints

- iOS 17+ only and no new dependency.
- Do not change existing `WKWebsiteDataStore` identifiers.
- Do not persist, log, upload, or expose the authorization URL, authorization code, callback URL, PKCE values, cookies, or OAuth tokens.
- Keep Cockpit Tools PC as the OAuth client and credential owner; iOS captures and locally copies only a validated callback.
- Keep device-code authorization as a fallback.
- Fail closed for malformed/deceptive URLs, duplicated critical parameters, or callback/state mismatches.
- Add Vietnamese and English copy for every new user-facing string.
- Push implementation and release artifacts only to the private `personal` repository; leave public `origin/main` unchanged.

## Review Focus

- Hosted `chatgpt.com/codex/desktop-auth` links whose nested `authorize_url` is malformed or points off OpenAI must be rejected by Task 1 tests.
- Lookalike hosts, URL credentials, fragments, duplicate `state`/`redirect_uri`/PKCE fields, and missing explicit callback ports must be rejected by Task 1 tests.
- A loopback callback with the wrong host, port, path, state, missing code, or duplicated code/state must never be copied and must leave the attempt retryable in Task 2 tests.
- Dismissing or dismantling the mapped browser must clear transient OAuth state and callback data in Task 2 tests.
- Narrow account cards, English strings, VoiceOver identifiers, and result-sheet clipboard clearing must remain usable in Task 3 UI tests and simulator previews.

---

### Task 1: Pure Cockpit OAuth URL and callback validation

**Files:**
- Create: `CodexCockpit/Services/CockpitOAuthRelay.swift`
- Create: `CodexCockpitTests/CockpitOAuthRelayTests.swift`

**Interfaces:**
- Produces: `CockpitOAuthAttempt: Hashable`, containing `authorizationURL`, exact expected callback components, and `state`.
- Produces: `CockpitOAuthCallback: Identifiable, Hashable`, containing only the validated callback URL.
- Produces: `CockpitOAuthCallbackInspection: Equatable` with `.notCallback`, `.captured(CockpitOAuthCallback)`, and `.rejected(CockpitOAuthRelayError)`.
- Produces: `CockpitOAuthRelay.prepare(_ rawURL: String) throws -> CockpitOAuthAttempt`.
- Produces: `CockpitOAuthRelay.inspectCallback(_ url: URL, for attempt: CockpitOAuthAttempt) -> CockpitOAuthCallbackInspection`.
- Produces: `CockpitOAuthRelayError: Error, Equatable` with a stable `localizationKey` and no secret-bearing associated text.

- [ ] **Step 1: Write failing parser tests**

Add tests for a valid Cockpit hosted URL, a valid direct inner authorize URL, exact extraction of callback/state, malformed nested URL, deceptive outer/inner hosts, credentials/fragments, missing or duplicate critical query items, non-`code` response type, non-S256 PKCE, empty challenge/state/client ID, and redirect URIs that are non-HTTP, non-loopback, lack an explicit port, or use a path other than `/auth/callback`.

- [ ] **Step 2: Run the private macOS CI test job and verify RED**

Run the `Build unsigned IPA` workflow on a temporary private test branch containing only the tests and design commits. Expected: compile failure because `CockpitOAuthRelay`, `CockpitOAuthAttempt`, and related types do not exist.

- [ ] **Step 3: Implement the minimal pure validator**

Use `URLComponents.queryItems` while preserving multiplicity. Accept only exact HTTPS outer `chatgpt.com/codex/desktop-auth` or exact HTTPS inner `auth.openai.com/oauth/authorize`; recursively validate the single outer `authorize_url`. Require one each of `client_id`, `response_type=code`, `redirect_uri`, `state`, `code_challenge`, and `code_challenge_method=S256`. Require an HTTP loopback callback on exact `localhost` or `127.0.0.1`, explicit port `1...65535`, path `/auth/callback`, and no credentials/query/fragment.

- [ ] **Step 4: Write failing callback-inspection tests**

Cover a valid callback plus non-callback HTTPS navigation, callback lookalikes, wrong loopback host/port/path, missing or duplicate code/state, fragment/userinfo, and same-length/different-state mismatch.

- [ ] **Step 5: Implement callback inspection and constant-time state comparison**

Classify ordinary HTTPS navigation as `.notCallback`; classify loopback or `/auth/callback` attempts as captured/rejected. Compare UTF-8 state bytes without early exit and never include callback data in error descriptions.

- [ ] **Step 6: Run focused and full tests GREEN**

Run the private macOS workflow. Expected: all XCTest/XCUITest cases pass and the unsigned build completes.

- [ ] **Step 7: Commit**

```bash
git add CodexCockpit/Services/CockpitOAuthRelay.swift CodexCockpitTests/CockpitOAuthRelayTests.swift
git commit -m "feat: validate Cockpit OAuth relay URLs"
```

### Task 2: WebKit callback interception and transient browser state

**Files:**
- Modify: `CodexCockpit/Web/BrowserState.swift`
- Modify: `CodexCockpit/Web/ProfileWebView.swift`
- Modify: `CodexCockpitTests/CockpitOAuthRelayTests.swift`

**Interfaces:**
- Consumes: `CockpitOAuthAttempt`, `CockpitOAuthCallback`, `CockpitOAuthCallbackInspection`, and `CockpitOAuthRelay.inspectCallback` from Task 1.
- Produces: `BrowserState.prepareCockpitOAuth(_ attempt: CockpitOAuthAttempt)`.
- Produces: `BrowserState.handleCockpitOAuthNavigation(_ url: URL) -> Bool`, returning `true` only when navigation must be cancelled as a callback/callback error.
- Produces: `BrowserState.clearCockpitOAuth()` and published read-only `cockpitOAuthAttempt` / `capturedCockpitOAuthCallback`.

- [ ] **Step 1: Write failing browser-state tests**

Assert that preparation opens the validated authorization URL, a valid callback is captured and clears the pending attempt, a state mismatch is cancelled but keeps the attempt retryable, ordinary HTTPS navigation is allowed, and explicit clear removes both pending/captured state.

- [ ] **Step 2: Run the focused test job and verify RED**

Expected: failures for missing browser-state APIs.

- [ ] **Step 3: Implement transient state and delegate interception**

Add published read-only properties and safe error localization keys to `BrowserState`. In `ProfileWebView.Coordinator.decidePolicyFor`, call `handleCockpitOAuthNavigation` before the generic scheme policy and cancel captured/rejected callback navigation. Clear OAuth state from `stopObserving` alongside the device fill task.

- [ ] **Step 4: Run focused and full tests GREEN**

Expected: callback tests and the existing device-code suite pass; no loopback callback reaches `UIApplication.open`.

- [ ] **Step 5: Commit**

```bash
git add CodexCockpit/Web/BrowserState.swift CodexCockpit/Web/ProfileWebView.swift CodexCockpitTests/CockpitOAuthRelayTests.swift
git commit -m "feat: capture Cockpit OAuth callbacks in WebKit"
```

### Task 3: Account actions, OAuth entry/result UI, and browser routing

**Files:**
- Create: `CodexCockpit/Views/CockpitOAuthRelaySheet.swift`
- Modify: `CodexCockpit/Models/AccountProfile.swift`
- Modify: `CodexCockpit/Views/AccountsView.swift`
- Modify: `CodexCockpit/Views/ProfileDetailView.swift`
- Modify: `CodexCockpit/en.lproj/Localizable.strings`
- Modify: `CodexCockpit/vi.lproj/Localizable.strings`
- Modify: `CodexCockpitTests/LocalizationTests.swift`
- Modify: `CodexCockpitUITests/LaunchTests.swift`

**Interfaces:**
- Consumes: `CockpitOAuthRelay.prepare`, `CockpitOAuthAttempt`, `CockpitOAuthCallback`, and Task 2 browser-state APIs.
- Produces: `BrowserMode.cockpitOAuth` and `BrowserLaunch.cockpitOAuth(_ attempt: CockpitOAuthAttempt)` while preserving existing `.web` and device initializers.
- Produces: `CockpitOAuthEntrySheet(accountName:identity:onOpen:)` and `CockpitOAuthResultSheet(callback:onClear:)`.

- [ ] **Step 1: Write failing localization and UI tests**

Require Vietnamese and English labels/instructions/errors, a `cockpit-oauth-entry` sheet identifier, a paste field, an open button disabled until valid input, and a `cockpit-oauth-result` success state with copy/clear controls. Add preview launch environments for entry and result states.

- [ ] **Step 2: Run the private macOS workflow and verify RED**

Expected: localization assertions and XCUITest element lookup fail because the UI and keys are absent.

- [ ] **Step 3: Implement route and reusable sheets**

Add the OAuth browser launch mode/attempt, localized validation without echoing secret URLs, local paste/copy actions, mapped identity display, and accessibility identifiers. Keep transient input/result only in SwiftUI and `BrowserState` memory.

- [ ] **Step 4: Wire account list, detail, and browser UI**

Add compact **OAuth** beside WebKit and Code actions, a detail action tile, and an OAuth menu item in the browser. On valid entry, route to the account's mapped WebKit and call `prepareCockpitOAuth`. On capture, auto-copy the exact callback, present the result sheet, allow recopy, and clear clipboard only when it still equals that callback.

- [ ] **Step 5: Keep device flow and narrow layout intact**

Use short action labels and adaptive layout so the account card still fits without horizontal scrolling. Confirm device-code entry, retry bar, clear-session flow, identity detection, and both navigation stacks still work.

- [ ] **Step 6: Run focused and full tests GREEN**

Expected: all unit/UI tests pass in Vietnamese and English.

- [ ] **Step 7: Commit**

```bash
git add CodexCockpit/Models/AccountProfile.swift CodexCockpit/Views/CockpitOAuthRelaySheet.swift CodexCockpit/Views/AccountsView.swift CodexCockpit/Views/ProfileDetailView.swift CodexCockpit/en.lproj/Localizable.strings CodexCockpit/vi.lproj/Localizable.strings CodexCockpitTests/LocalizationTests.swift CodexCockpitUITests/LaunchTests.swift
git commit -m "feat: add Cockpit OAuth relay UI"
```

### Task 4: Documentation, previews, version, and release verification

**Files:**
- Modify: `README.md`
- Modify: `.github/workflows/build-unsigned-ipa.yml`
- Modify: `project.yml`
- Modify: `scripts/verify_project.py` only if the new service changes its explicit file/security assertions.

**Interfaces:**
- Consumes: the complete flow from Tasks 1-3.
- Produces: version `1.7.0`, Vietnamese/English OAuth-entry and callback-result preview artifacts, and an unsigned private IPA.

- [ ] **Step 1: Document the no-VPS two-paste flow and security boundary**

Explain that Cockpit PC starts Browser OAuth and owns tokens; iOS reuses the mapped WebKit and returns only the validated callback. Retain the device-code fallback instructions and state that callback URLs must never be shared.

- [ ] **Step 2: Extend preview capture and bump version**

Capture `cockpit-oauth-entry(.png|-en.png)` and `cockpit-oauth-result(.png|-en.png)` through deterministic preview environments. Set `MARKETING_VERSION=1.7.0` and increment the build number once.

- [ ] **Step 3: Run local static checks**

Run:

```powershell
python scripts\verify_project.py
git diff --check
git status --short
```

Expected: static verification passes, no whitespace errors, and only intended files are changed.

- [ ] **Step 4: Run final private CI**

Push the branch to `personal`, dispatch `Build unsigned IPA`, and verify unit/UI tests, simulator previews, unsigned device build, IPA packaging, and artifact uploads all succeed.

- [ ] **Step 5: Inspect visual artifacts**

Download and visually inspect both languages' account list, OAuth entry, mapped browser pending state, and callback result. Fix clipping, cramped actions, leaked URL/code text, or unclear instructions and rerun CI if needed.

- [ ] **Step 6: Commit final docs/version/workflow changes**

```bash
git add README.md .github/workflows/build-unsigned-ipa.yml project.yml scripts/verify_project.py
git commit -m "release: prepare Cockpit OAuth relay 1.7.0"
```

- [ ] **Step 7: Release privately and preserve public main**

Create a private personal release containing the unsigned IPA and OAuth preview images, record the IPA SHA-256, and verify `origin/main` remains at its pre-feature commit.
