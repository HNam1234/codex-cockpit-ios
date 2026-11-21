# Codex Cockpit iOS

SwiftUI app for iOS 17+ with a native quota dashboard and a dynamic number of persistent, isolated WebKit profiles.

## Features

- Soor/Apple Music-inspired native visual system: editorial gradients, artwork-style account identities, adaptive materials, large type, and compact one-hand navigation.
- The home screen fits all configured accounts in compact live-quota rows. Its small TIBO strip shows the latest reset-relevant public X post and an explicitly estimated probability of a reset today.
- Pull down on the overview to refresh every account quota and then reload the consolidated dashboard state.
- Compact native overview with correct remaining-quota progress bars; tap an account for full reset times and actions.
- Dynamic account count and dynamic independent ChatGPT sessions backed by persistent `WKWebsiteDataStore` identifiers.
- Account names and account-to-WebKit mappings reconcile automatically with the signed-in ChatGPT identity. Manual remapping remains available and swaps mappings without clearing cookies.
- Optional local TIBO notifications explain the public signal, avoid duplicate alerts, and never include private account data.
- Reauthorize a revoked Codex account through the VPS device-login flow, then confirm inside the account's mapped WebKit.
- Refresh usage and consume a real reset credit from the native account screen when the Codex account exposes one.
- One global TIBO reset banner fetched by the VPS from the public OpenTheRank tracker every 15 minutes. No account data is sent to TIBO or OpenTheRank.
- Device-code entry opens `auth.openai.com/codex/device` inside the selected profile and attempts to fill the code. The user still confirms on the official OpenAI page.
- Device code is only copied to the local iPhone clipboard; the app does not upload it.
- Per-profile clear-session action. The original five data-store UUIDs remain unchanged, so installing an update over the existing app with the same Bundle ID preserves their logins.
- Launches directly into the dashboard; the unstable startup Face ID gate is disabled.
- Face ID preference uses a namespaced key so re-signing with a reused bundle ID cannot inherit another app's lock state.
- Up to two profile WebViews stay warm in an LRU pool for instant device-login entry while preserving each profile's isolated persistent session.

## Generate and run

Requires macOS, Xcode with the iOS 17+ SDK, and XcodeGen:

```bash
brew install xcodegen
xcodegen generate
open CodexCockpit.xcodeproj
```

In Xcode, select the `CodexCockpit` target, choose your Apple Developer Team, connect the registered iPhone, and Run. The bundle ID defaults to `vn.nam.CodexCockpit`; change it if the developer account already uses that identifier.

## Unsigned IPA and ESign

The GitHub workflow builds and tests an **unsigned** IPA. Download the `CodexCockpit-unsigned` artifact from a successful `Build unsigned IPA` run, then sign it on the iPhone with ESign and the repository owner's provisioning profile.

Keep the bundle ID `vn.nam.CodexCockpit` and install over the existing app to preserve its WebKit data. The project intentionally avoids entitlements that require special provisioning, such as App Groups, Associated Domains, and Push Notifications.

Do not send Apple passwords, certificates, provisioning profiles, signing keys, or ESign credentials in chat or commit them to the repository.

## Native dashboard authentication

Public source code, build logs, and release IPAs contain no dashboard credential. On the iPhone, open **Cài đặt → Kết nối VPS**, enter the revocable `COCKPIT_APP_TOKEN` supplied by the deployment administrator, and save it. The token is validated and stored only in that device's iOS Keychain; the app never displays the saved value again.

The token is posted in the HTTPS request body, never placed in a URL. Disconnecting from Settings removes it from Keychain and clears the loaded dashboard state.

The account list is loaded dynamically and is not capped at five. Install upgrades over the existing app with the same Bundle ID and signing team. Changing the Bundle ID or deleting the app creates/removes the iOS sandbox, so WebKit cookies cannot be carried across that boundary.

## Current validation boundary

The macOS CI workflow builds the IPA and runs the Xcode unit/UI tests. Device-login confirmation still happens on the official OpenAI page; third-party SSO providers may choose to redirect outside embedded web views.

## Public release IPA

GitHub Releases publish an **unsigned** IPA built from the tagged public source. It must be re-signed with an Apple Developer certificate or installed through a compatible sideloading service before iOS will run it. A token is entered after installation and is not bundled with the IPA.
