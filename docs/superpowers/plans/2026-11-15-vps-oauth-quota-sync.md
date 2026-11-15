# VPS OAuth Quota Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import direct WebKit OAuth into the mapped VPS account and display a live native quota snapshot immediately.

**Architecture:** A tested Python credential-import module validates and transactionally installs Codex `auth.json`; the existing dashboard server exposes it through one authenticated native endpoint. The Swift API/store sends the verified registration and replaces the account snapshot, while foreground recovery syncs only broken mapped slots.

**Tech Stack:** Python 3 standard library, Codex app-server 0.167.0, Swift 5, SwiftUI, XCTest, Tailscale HTTPS, GitHub Actions macOS runner.

**Spec:** `docs/superpowers/specs/2026-11-15-vps-oauth-quota-sync-design.md`

## Global Constraints

- Never log, render, or commit OAuth tokens.
- Preserve each existing WebKit data-store identifier and explicit account mapping.
- Roll back the prior `auth.json` if live Codex snapshot validation fails.
- Keep device-code authorization as fallback.
- Keep Vietnamese and English UI support and iOS 17 compatibility.
- Release only to the `personal` repository; do not change public `origin/main`.

## Review Focus

- Malformed JWTs and mismatched client/subject/account claims must fail before writing credentials.
- A failed or timed-out Codex snapshot must restore the exact old credential bytes.
- A stale Keychain registration must not overwrite an already healthy VPS slot on foreground.
- A successful import must replace the correct remote account snapshot, not create a duplicate local account.
- Token values must remain absent from logs, localized errors, git diffs, and release artifacts.

---

### Task 1: Transactional Codex credential import

**Files:**
- Create: `backend/codex_oauth_import.py`
- Create: `backend/tests/test_codex_oauth_import.py`

**Interfaces:**
- Produces: `build_auth_document(client_id, id_token, access_token, refresh_token, *, now, login_owner_id) -> tuple[dict, ImportedIdentity]`.
- Produces: `install_and_verify(auth_path, document, snapshot_reader) -> dict`, restoring the prior file on every validation failure.

- [ ] Write tests for matched credentials, malformed JWTs, claim mismatches, secure output mode, live snapshot success, and byte-for-byte rollback.
- [ ] Run `python -m unittest backend.tests.test_codex_oauth_import -v`; expect RED because the module is absent.
- [ ] Implement the minimal validator and transactional writer.
- [ ] Run the focused test GREEN and commit.

### Task 2: Authenticated VPS import endpoint

**Files:**
- Modify on VPS: `/opt/codex-cockpit/server.py`
- Deploy from repo: `backend/codex_oauth_import.py`
- Create: `backend/README.md`

**Interfaces:**
- Consumes: Task 1 `build_auth_document` and `install_and_verify`.
- Produces: `POST /app-auth/import`, accepting one explicit account ID and verified OAuth fields, returning `{"account": AccountSnapshot}`.

- [ ] Add a failing endpoint integration test using fake credentials and a fake snapshot reader.
- [ ] Add the route, a 32 KiB request cap, state snapshot persistence, token-safe errors, and per-account serialization.
- [ ] Deploy with a timestamped server backup, restart, and verify health plus rejection of malformed credentials.
- [ ] Confirm all five existing account snapshots remain readable.

### Task 3: iOS import and immediate quota update

**Files:**
- Modify: `CodexCockpit/Services/CockpitAPI.swift`
- Modify: `CodexCockpit/Services/CockpitStore.swift`
- Modify: `CodexCockpit/Views/ProfileDetailView.swift`
- Modify: `CodexCockpitTests/CockpitStoreTests.swift`

**Interfaces:**
- Produces: `CockpitAPIClient.importDirectOAuth(accountID:registration:) async throws -> AccountSnapshot`.
- Produces: `CockpitStore.importDirectOAuth(accountID:registration:) async -> AccountSnapshot?`.

- [ ] Add a failing store test proving import replaces the correct remote snapshot with live quota.
- [ ] Implement API form encoding and store replacement.
- [ ] Await VPS import after direct OAuth before presenting success; show a token-safe sync error on failure.
- [ ] Run static verification and private macOS tests GREEN.

### Task 4: Recovery, account creation, version, and release

**Files:**
- Modify: `CodexCockpit/Views/RootView.swift`
- Modify: `CodexCockpit/Views/AccountsView.swift`
- Modify: `CodexCockpit/en.lproj/Localizable.strings`
- Modify: `CodexCockpit/vi.lproj/Localizable.strings`
- Modify: `project.yml`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 3 import API and existing profile mapping.
- Produces: one-time foreground recovery for broken remote slots and VPS-first add-account behavior.

- [ ] Add tests proving healthy slots are skipped and broken mapped slots are eligible for recovery.
- [ ] Create new accounts on the VPS before allocating/opening their WebKit.
- [ ] Sync saved registrations only for remote slots that need login/quota, then render returned quota.
- [ ] Bump to `1.10.0`, run the full verification workflow, inspect previews, and publish the personal IPA release.

