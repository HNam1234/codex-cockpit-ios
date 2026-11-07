# Codex Cockpit iOS

SwiftUI prototype for iOS 17+ with one dashboard session and five persistent, isolated WebKit profiles.

## Features

- Existing Codex quota dashboard inside the app.
- Five independent ChatGPT web sessions backed by fixed `WKWebsiteDataStore` identifiers.
- Device-code entry opens `auth.openai.com/codex/device` inside the selected profile and attempts to fill the code. The user still confirms on the official OpenAI page.
- Device code is only copied to the local iPhone clipboard; the app does not upload it.
- Per-profile clear-session action.
- Optional Face ID/device-passcode lock.
- Face ID preference uses a namespaced key so re-signing with a reused bundle ID cannot inherit another app's lock state.
- Only one profile WebView is alive while its screen is open.

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

### Private CI option (no Mac required locally)

The `build-signed-ipa.yml` workflow builds on a macOS GitHub runner. Use a **private** repository and add these secrets; never commit the values:

- `APPLE_TEAM_ID`
- `APPLE_SIGNING_IDENTITY` (`Apple Distribution` for Ad Hoc, or `Apple Development`)
- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `CI_KEYCHAIN_PASSWORD`

Optionally set repository variable `IOS_BUNDLE_ID`. The provisioning profile must match that bundle ID and include the target iPhone UDID for Ad Hoc/development installation.

## Dashboard login

Send `/web` to the Telegram bot, copy the short-lived login URL, then use the link button in the Cockpit tab to paste it once. The dashboard cookie remains in its own isolated WebKit store.

## Current validation boundary

The repository includes static checks and Xcode unit tests, but this Windows machine cannot compile an iOS binary. The first device build must verify that the selected ChatGPT sign-in method works inside `WKWebView`; third-party SSO providers may choose to redirect outside embedded web views.
