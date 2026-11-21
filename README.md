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

## Export a signed IPA

Register the iPhone UDID in the Apple Developer account, create/refresh a Development or Ad Hoc provisioning profile, archive the app in Xcode, then choose **Distribute App** and export for the registered device. Developer Mode must be enabled on the iPhone.

Do not send Apple passwords, signing private keys, `.p12` passwords, or App Store Connect private keys in chat. Keep signing assets in Xcode Keychain or a private CI secret store.

If Xcode is already signed into the paid Apple Developer account, the included script generates a development-signed IPA:

```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/build_signed_ipa.sh
```

The iPhone UDID must belong to the provisioning profile. For installation, use Xcode Devices and Simulators, Apple Configurator, or the Apple Devices workflow approved for the profile.

### Signed CI option (no Mac required locally)

The `build-signed-ipa.yml` workflow builds on a macOS GitHub runner. Add these GitHub Actions secrets; never commit the values or expose them to pull-request code:

- `APPLE_TEAM_ID`
- `APPLE_SIGNING_IDENTITY` (`Apple Distribution` for Ad Hoc, or `Apple Development`)
- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `CI_KEYCHAIN_PASSWORD`

Optionally set repository variable `IOS_BUNDLE_ID`. The provisioning profile must match that bundle ID and include the target iPhone UDID for Ad Hoc/development installation.

## Native dashboard authentication

Public source code, build logs, and release IPAs contain no dashboard credential. On the iPhone, open **Cài đặt → Kết nối VPS**, enter the revocable `COCKPIT_APP_TOKEN` supplied by the deployment administrator, and save it. The token is validated and stored only in that device's iOS Keychain; the app never displays the saved value again.

The token is posted in the HTTPS request body, never placed in a URL. Disconnecting from Settings removes it from Keychain and clears the loaded dashboard state.

The account list is loaded dynamically and is not capped at five. Install upgrades over the existing app with the same Bundle ID and signing team. Changing the Bundle ID or deleting the app creates/removes the iOS sandbox, so WebKit cookies cannot be carried across that boundary.

## Current validation boundary

The macOS CI workflow builds the IPA and runs the Xcode unit/UI tests. Device-login confirmation still happens on the official OpenAI page; third-party SSO providers may choose to redirect outside embedded web views.

## Public release IPA

GitHub Releases publish an **unsigned** IPA built from the tagged public source. It must be re-signed with an Apple Developer certificate or installed through a compatible sideloading service before iOS will run it. A token is entered after installation and is not bundled with the IPA.
