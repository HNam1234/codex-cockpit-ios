# Codex Cockpit VPS bridge

`codex_oauth_import.py` is the token-safe, tested part of the personalized VPS integration. It validates the two OpenAI JWT claim sets, creates the Codex `auth.json` format used by Codex 0.167.0, writes it with private permissions, and retains it only after a real Codex app-server quota snapshot succeeds.

The production dashboard integration is recorded in the zero-context `vps-server-auth-import.patch` (validate with `git apply --check --unidiff-zero`). It adds authenticated `POST /app-auth/import` to `/opt/codex-cockpit/server.py`; the route accepts `account_id`, `client_id`, `id_token`, `access_token`, and `refresh_token`, then returns the existing `AccountEnvelope` shape.

Deployment keeps a timestamped `/opt/codex-cockpit/server.py.bak-*` backup, installs both Python files as root-owned mode `0644`, compiles them, restarts `codex-cockpit.service`, checks `/codex/api/health`, and confirms existing account credential hashes are unchanged. `smoke_account_registry.py` verifies that the hardened service can create and recoverably delete a temporary account. OAuth values must never be printed while deploying or diagnosing this bridge.

