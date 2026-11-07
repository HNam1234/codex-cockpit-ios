#!/usr/bin/env python3
import json
import re
from pathlib import Path

root = Path(__file__).parents[1]
swift = list((root / "CodexCockpit").rglob("*.swift"))
assert len(swift) >= 10, f"expected Swift sources, got {len(swift)}"

profile_source = (root / "CodexCockpit/Models/AccountProfile.swift").read_text(encoding="utf-8")
assert "static func persistentIdentifier(for id: String)" in profile_source
assert "These five identifiers shipped in 1.0.x" in profile_source
assert "ProfileMappingStore" in profile_source
assert "WKWebsiteDataStore(forIdentifier:" in (root / "CodexCockpit/Services/ProfileDataStore.swift").read_text(encoding="utf-8")
assert "auth.openai.com/codex/device" in profile_source
assert "openDeviceLogin" in (root / "CodexCockpit/Web/BrowserState.swift").read_text(encoding="utf-8")
api_source = (root / "CodexCockpit/Services/CockpitAPI.swift").read_text(encoding="utf-8")
for endpoint in ("app-status", "app-auth/start", "app-auth/status", "app-reset-credit"):
    assert endpoint in api_source
assert "tiboReset" in profile_source

for path in (root / "CodexCockpit/Assets.xcassets").rglob("Contents.json"):
    json.loads(path.read_text(encoding="utf-8"))

all_text = "\n".join(path.read_text(encoding="utf-8") for path in swift)
for forbidden in ("telegram_bot_token", "password =", "auth.json", "BEGIN PRIVATE KEY"):
    assert forbidden not in all_text, f"forbidden secret-like string: {forbidden}"

assert not re.search(r"\b\d{8,12}:[A-Za-z0-9_-]{30,}\b", all_text), "Telegram bot token-like value found"

print(f"static verification passed: {len(swift)} Swift files, dynamic isolated stores, no embedded secrets")
