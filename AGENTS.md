# AGENTS.md

- Work plan (single source of truth): `docs/codex-ux-plan.md`. Follow section 4 in order, one commit per task, on branch `ux/fast-device-code`.
- The repo owner (HNam1234) authorizes pushing fast-forward to `main` at each milestone, signing in to GitHub via `gh auth login --web` (owner confirms the one-time code), and running the CI workflows. Never force-push or rewrite `main`. Never change repo settings, secrets, branch protection or collaborators.
- Never commit `ops/`, `tmp/`, `work/`.
- Never change `WebProfile.persistentIdentifier(for:)`, the five original data-store UUIDs, or the bundle ID `vn.nam.CodexCockpit`.
- Never send device codes, ChatGPT emails/passwords or cookies to the VPS or any host other than the OpenAI page open in the WebView. Never auto-click Authorize/Login.
- Local machine is Windows without Xcode: run `python scripts/verify_project.py` before each commit; Swift build and tests run on the macOS CI. Do not start new work while `main` CI is red.
- The VPS backend (`/opt/codex-cockpit/server.py`) is not in git; do not edit it without the owner's approval.
- UI text is Vietnamese; reuse `Views/DesignSystem.swift`.
