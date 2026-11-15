"""Create and recoverably delete one temporary account through the live bridge."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys


SERVER_PATH = Path("/opt/codex-cockpit/server.py")
sys.path.insert(0, str(SERVER_PATH.parent))
spec = importlib.util.spec_from_file_location("codex_cockpit_registry_smoke", SERVER_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("Could not load dashboard server")
server = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = server
spec.loader.exec_module(server)

bridge = server.AppActionBridge(server.CONFIG_PATH)
existing = server.read_json(server.CONFIG_PATH, {}).get("accounts") or []
for stale in existing:
    if str(stale.get("name") or "") == "Codex registry smoke":
        bridge.delete_account(str(stale["id"]))

before = server.read_json(server.CONFIG_PATH, {}).get("accounts") or []
before_ids = {str(item.get("id")) for item in before}
created = bridge.create_account("Codex registry smoke")
created_id = str(created["id"])
try:
    if created_id in before_ids:
        raise RuntimeError("Smoke account reused an existing ID")
finally:
    bridge.delete_account(created_id)

after = server.read_json(server.CONFIG_PATH, {}).get("accounts") or []
after_ids = {str(item.get("id")) for item in after}
if after_ids != before_ids:
    raise RuntimeError("Account registry did not return to its original membership")
print(json.dumps({"created": True, "deleted": True, "membership_restored": True}))
