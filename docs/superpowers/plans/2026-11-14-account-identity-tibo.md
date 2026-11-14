# Account Identity Sync and TIBO Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically keep account names and WebKit mappings aligned with the signed-in ChatGPT identity and deliver clearer, deduplicated TIBO alerts.

**Architecture:** A small Codable identity model and `ProfileMappingStore` own local identity caching and exact-email reconciliation. `ProfileWebView` probes the same-origin authenticated session after navigation. A pure TIBO policy builds alert content, while a UserNotifications-backed manager handles opt-in permission and deduplication; SwiftUI owns polling and presentation.

**Tech Stack:** Swift 5, SwiftUI, WebKit, UserNotifications, XCTest, iOS 17+

**Spec:** `docs/superpowers/specs/2026-11-14-account-identity-tibo-design.md`

## Global Constraints

- Do not change the original five persistent WebKit identifiers.
- Do not transmit cookies, tokens, or WebKit storage.
- Never remap by display name alone; automatic remapping requires one unique normalized email match.
- Request notification permission only from an explicit user toggle.
- Add no third-party dependencies.

## Review Focus

- Missing/blank JavaScript fields must not create a fake identity.
- Duplicate or case-varied emails must not remap ambiguously.
- A WebKit identity must survive quota/API errors and remain local to its profile.
- Repeated TIBO payloads must not generate repeated alerts.
- Stale, `no`, and `unknown` TIBO states must never generate local alerts.

---

### Task 1: Local WebKit Identity and Mapping Reconciliation

**Files:**
- Create: `CodexCockpit/Models/WebAccountIdentity.swift`
- Modify: `CodexCockpit/Models/AccountProfile.swift`
- Create: `CodexCockpitTests/ProfileMappingTests.swift`

**Interfaces:**
- Produces: `WebAccountIdentity`, `ProfileMappingStore.record(identity:for:accounts:)`, `displayIdentity(for:)`, `clearIdentity(for:)`.

- [ ] Write XCTest cases for trimming/blank rejection, unique case-insensitive email swaps, ambiguous email preservation, cached display fallback, persistence, and clearing.
- [ ] Run the focused XCTest target and confirm it fails because the new identity API is absent.
- [ ] Implement the minimal Codable model, injectable UserDefaults storage, exact-email reconciliation, and display fallback.
- [ ] Run the focused tests and confirm they pass.

### Task 2: WebView Identity Probe and UI Wiring

**Files:**
- Modify: `CodexCockpit/Web/ProfileWebView.swift`
- Modify: `CodexCockpit/Views/ProfileDetailView.swift`
- Modify: `CodexCockpit/Views/CockpitView.swift`
- Modify: `CodexCockpit/Views/AccountsView.swift`

**Interfaces:**
- Consumes: `WebAccountIdentity` and the mapping-store methods from Task 1.
- Produces: `ProfileWebView.onIdentityDetected` callback.

- [ ] Add a failing parser test using literal JavaScript dictionaries and malformed values.
- [ ] Run the focused test and confirm the parser API is missing.
- [ ] Probe only `chatgpt.com` after finished navigation, return only name/email, and call the native callback.
- [ ] Wire the callback to mapping reconciliation, use mapped cached identity in account UIs, and clear it with the WebKit session.
- [ ] Run identity tests and static project verification.

### Task 3: TIBO Alert Policy and Notification Manager

**Files:**
- Create: `CodexCockpit/Models/TiboAlert.swift`
- Create: `CodexCockpit/Services/TiboNotificationManager.swift`
- Create: `CodexCockpitTests/TiboAlertTests.swift`
- Modify: `CodexCockpit/Views/SettingsView.swift`

**Interfaces:**
- Produces: `TiboAlertPolicy.content(for:)`, `TiboNotificationManager.process(_:)`, and an opt-in `isEnabled` setting.

- [ ] Write XCTest cases for `likely`, `yes`, stale/no/unknown suppression, stable identifiers, and status escalation.
- [ ] Run the focused test and confirm the policy API is missing.
- [ ] Implement pure alert content generation and the UserNotifications manager with persisted deduplication.
- [ ] Add the TIBO opt-in toggle and denied-permission feedback in Settings.
- [ ] Run the focused tests and static project verification.

### Task 4: Active Refresh and TIBO Presentation

**Files:**
- Modify: `CodexCockpit/Services/CockpitStore.swift`
- Modify: `CodexCockpit/Views/RootView.swift`
- Modify: `CodexCockpit/Views/CockpitView.swift`
- Modify: `CodexCockpitTests/ProfileTests.swift`
- Modify: `scripts/verify_project.py`

**Interfaces:**
- Consumes: TIBO notification manager and account identity mapping.
- Produces: `CockpitStore.pollSeconds` and foreground polling behavior.

- [ ] Add failing tests for poll interval clamping and TIBO presentation metadata.
- [ ] Run the focused tests and confirm the helpers are missing.
- [ ] Persist the response polling interval, reload immediately on active scene entry, and poll only while active.
- [ ] Redesign the TIBO card to show status, freshness, source link, and probability context without hiding the account list.
- [ ] Extend static verification for the new privacy and notification boundaries.
- [ ] Run all available unit/UI tests, project verification, and inspect the final diff for secrets and accidental WebKit identifier changes.
