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
direct_oauth_source = (root / "CodexCockpit/Services/DirectOAuthFlow.swift").read_text(encoding="utf-8")
for requirement in (
    "dynamic_agent_client",
    "code_challenge_method",
    "SecKeyVerifySignature",
    "email_verified",
    "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly",
):
    assert requirement in direct_oauth_source
assert "DirectOAuthStore" in direct_oauth_source
api_source = (root / "CodexCockpit/Services/CockpitAPI.swift").read_text(encoding="utf-8")
for endpoint in ("app-status", "app-auth/start", "app-auth/status", "app-reset-credit"):
    assert endpoint in api_source
assert "AppAuth.cockpitToken" in api_source
assert "tiboReset" in profile_source
assert "subscriptionExpiresAt" in profile_source
assert "subscriptionRemainingText" in profile_source
assert "createDedicatedProfile" in profile_source
assert "removeAccount" in profile_source

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
assert ".refreshable" in cockpit_source
assert "await store.refreshAll()" in cockpit_source
assert ".scrollBounceBehavior(.always)" in cockpit_source

workflow_text = "\n".join(
    path.read_text(encoding="utf-8")
    for path in (root / ".github/workflows").glob("*.yml")
)
assert "COCKPIT_APP_TOKEN" in workflow_text
assert (root / "scripts/generate_app_auth.py").exists()
assert not (root / "CodexCockpit/AppAuth.generated.swift").exists()

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

device_code_source = (root / "CodexCockpit/Services/DeviceCodeAssistant.swift").read_text(encoding="utf-8")
assert "callAsyncJavaScript" in device_code_source
assert "Task.sleep" in device_code_source
assert "input.focus()" in device_code_source
assert "input.value === code" in device_code_source
assert "button.click()" in device_code_source
assert "DeviceCodeAssistant.submit" in (root / "CodexCockpit/Web/BrowserState.swift").read_text(encoding="utf-8")

mail_client_source = (root / "CodexCockpit/Services/MailTMClient.swift").read_text(encoding="utf-8")
assert 'URL(string: "https://api.mail.tm")!' in mail_client_source
assert 'components.host?.lowercased() == "api.mail.tm"' in mail_client_source
assert "http://api.mail.tm" not in mail_client_source

mail_vault_source = (root / "CodexCockpit/Services/DisposableMailCredentialVault.swift").read_text(encoding="utf-8")
assert "kSecAttrAccessibleWhenUnlockedThisDeviceOnly" in mail_vault_source

mail_model_source = (root / "CodexCockpit/Models/DisposableMail.swift").read_text(encoding="utf-8")
mail_cache_source = (root / "CodexCockpit/Services/DisposableMailPersistence.swift").read_text(encoding="utf-8")
for forbidden_persisted_credential in ("password", "token"):
    assert forbidden_persisted_credential not in mail_model_source.lower()
    assert forbidden_persisted_credential not in mail_cache_source.lower()

mail_view_source = (root / "CodexCockpit/Views/MailView.swift").read_text(encoding="utf-8")
mailbox_view_source = (root / "CodexCockpit/Views/MailboxDetailView.swift").read_text(encoding="utf-8")
message_view_source = (root / "CodexCockpit/Views/DisposableMessageView.swift").read_text(encoding="utf-8")
assert ".refreshable" in mail_view_source
assert ".refreshable" in mailbox_view_source
for forbidden_renderer in ("WKWebView", "WebView", "NSAttributedString", "loadHTMLString"):
    assert forbidden_renderer not in message_view_source, f"remote mail renderer found: {forbidden_renderer}"
assert "VerificationCodeExtractor.codes" in message_view_source

accounts_source = (root / "CodexCockpit/Views/AccountsView.swift").read_text(encoding="utf-8")
assert 'L10n.text("accounts.add_with_webkit")' in accounts_source
assert "Code từ PC" in accounts_source
assert "startQuotaLogin" in accounts_source
assert "createAccount(name:" in accounts_source
assert "createLocalAccount" not in accounts_source
assert "beginReauthorization" in accounts_source
assert "recoverMappedOAuthQuota" not in root_source
assert "ProfileDataStore.clear" in accounts_source
assert "AccountQuotaSnapshot" in accounts_source
assert "window.remainingPercent" in accounts_source

pc_code_source = (root / "CodexCockpit/Views/DeviceAuthorizationSheet.swift").read_text(encoding="utf-8")
assert "codex login --device-auth" in pc_code_source
assert "VPS" not in pc_code_source
assert "beginReauthorization" not in pc_code_source

english_strings = (root / "CodexCockpit/en.lproj/Localizable.strings").read_text(encoding="utf-8")
vietnamese_strings = (root / "CodexCockpit/vi.lproj/Localizable.strings").read_text(encoding="utf-8")
for key in (
    "Nhập code từ PC",
    "Tiếp tục tự động",
    "Tổng quan",
    "Cài đặt",
    "quota.reset.hours_minutes",
    "subscription.days",
    "tibo.status.confirmed",
    "mail.tab",
    "mail.empty.title",
    "mail.create.title",
    "mail.lifetime.60",
    "mail.code.copy",
    "mail.provider.attribution",
    "oauth.direct.syncingQuota",
    "oauth.direct.error.quotaSync",
    "accounts.add_with_webkit",
    "accounts.creating",
):
    assert f'"{key}"' in english_strings, f"missing English localization: {key}"
    assert f'"{key}"' in vietnamese_strings, f"missing Vietnamese localization: {key}"
assert '"Nhập code từ PC" = "Enter code from PC";' in english_strings
assert '"Tiếp tục tự động" = "Continue automatically";' in english_strings
assert "developmentLanguage: vi" in (root / "project.yml").read_text(encoding="utf-8")
assert "cockpit-device-code-en.png" in workflow_text
for preview in (
    "cockpit-mail.png",
    "cockpit-mail-message.png",
    "cockpit-mail-en.png",
    "cockpit-mail-message-en.png",
):
    assert preview in workflow_text, f"missing Mail preview: {preview}"

project_text = (root / "project.yml").read_text(encoding="utf-8")
assert project_text.count('MARKETING_VERSION: "1.10.2"') == 1
assert project_text.count('CURRENT_PROJECT_VERSION: "28"') == 1

api_source = (root / "CodexCockpit/Services/CockpitAPI.swift").read_text(encoding="utf-8")
assert "app-account/create" in api_source
assert "app-account/delete" in api_source
assert "app-auth/import" in api_source

for path in (root / "CodexCockpit/Assets.xcassets").rglob("Contents.json"):
    json.loads(path.read_text(encoding="utf-8"))

all_text = "\n".join(path.read_text(encoding="utf-8") for path in swift)
for forbidden in ("telegram_bot_token", "password =", "auth.json", "BEGIN PRIVATE KEY"):
    assert forbidden not in all_text, f"forbidden secret-like string: {forbidden}"

assert not re.search(r"\b\d{8,12}:[A-Za-z0-9_-]{30,}\b", all_text), "Telegram bot token-like value found"

print(
    f"static verification passed: {len(swift)} Swift files, dynamic isolated stores, "
    "automatic private-build authentication, no committed secrets"
)
