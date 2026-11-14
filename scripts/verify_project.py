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

web_source = (root / "CodexCockpit/Web/ProfileWebView.swift").read_text(encoding="utf-8")
assert "onIdentityDetected" in web_source
for forbidden_web_read in ("document.cookie", "localStorage", "sessionStorage"):
    assert forbidden_web_read not in web_source, f"forbidden WebKit secret read: {forbidden_web_read}"

notification_source = (root / "CodexCockpit/Services/TiboNotificationManager.swift").read_text(encoding="utf-8")
assert "requestAuthorization" in notification_source
assert "historyKey" in notification_source
assert "TiboAlertPolicy.content" in notification_source

root_source = (root / "CodexCockpit/Views/RootView.swift").read_text(encoding="utf-8")
assert ".task(id: scenePhase)" in root_source
assert "scenePhase == .active" in root_source
assert "identityScanner.scan" in root_source

cockpit_source = (root / "CodexCockpit/Views/CockpitView.swift").read_text(encoding="utf-8")
assert ".refreshable { await store.refreshAll() }" in cockpit_source
assert ".scrollBounceBehavior(.always)" in cockpit_source

scanner_source = (root / "CodexCockpit/Services/WebIdentityScanner.swift").read_text(encoding="utf-8")
assert "ProfileDataStore.store" in scanner_source
assert "AppURLs.chatGPTSession" in scanner_source
assert "JSONSerialization" not in scanner_source
assert "WebIdentityBridge.identityFromSessionDocument" in scanner_source
for forbidden_scanner_read in ("document.cookie", "localStorage", "sessionStorage"):
    assert forbidden_scanner_read not in scanner_source, f"forbidden scanner secret read: {forbidden_scanner_read}"

bridge_source = (root / "CodexCockpit/Services/WebIdentityBridge.swift").read_text(encoding="utf-8")
assert "callAsyncJavaScript" in bridge_source
assert "/api/auth/session" in bridge_source
assert "return name || email ? { name: name || null, email: email || null } : null" in bridge_source

for path in (root / "CodexCockpit/Assets.xcassets").rglob("Contents.json"):
    json.loads(path.read_text(encoding="utf-8"))

all_text = "\n".join(path.read_text(encoding="utf-8") for path in swift)
for forbidden in ("telegram_bot_token", "password =", "auth.json", "BEGIN PRIVATE KEY"):
    assert forbidden not in all_text, f"forbidden secret-like string: {forbidden}"

assert not re.search(r"\b\d{8,12}:[A-Za-z0-9_-]{30,}\b", all_text), "Telegram bot token-like value found"

print(f"static verification passed: {len(swift)} Swift files, dynamic isolated stores, no embedded secrets")
