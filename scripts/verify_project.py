#!/usr/bin/env python3
import json
import re
from pathlib import Path

root = Path(__file__).parents[1]
swift = list((root / "CodexCockpit").rglob("*.swift"))
assert len(swift) >= 10, f"expected Swift sources, got {len(swift)}"

profile_source = (root / "CodexCockpit/Models/AccountProfile.swift").read_text(encoding="utf-8")
uuids = re.findall(r'UUID\(uuidString: "([A-F0-9-]+)"\)', profile_source)
assert len(uuids) == 6, uuids
assert len(set(uuids)) == 6
assert "WKWebsiteDataStore(forIdentifier:" in (root / "CodexCockpit/Services/ProfileDataStore.swift").read_text(encoding="utf-8")
assert "auth.openai.com/codex/device" in profile_source
assert "openDeviceLogin" in (root / "CodexCockpit/Web/BrowserState.swift").read_text(encoding="utf-8")
assert "/codex/app-login" in profile_source

for path in (root / "CodexCockpit/Assets.xcassets").rglob("Contents.json"):
    json.loads(path.read_text(encoding="utf-8"))

all_text = "\n".join(path.read_text(encoding="utf-8") for path in swift)
for forbidden in ("telegram_bot_token", "password =", "auth.json", "BEGIN PRIVATE KEY"):
    assert forbidden not in all_text, f"forbidden secret-like string: {forbidden}"

assert not re.search(r"\b\d{8,12}:[A-Za-z0-9_-]{30,}\b", all_text), "Telegram bot token-like value found"

print(f"static verification passed: {len(swift)} Swift files, 6 isolated stores, no embedded secrets")
