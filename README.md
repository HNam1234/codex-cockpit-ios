# Codex Cockpit iOS

SwiftUI app for iOS 17+ with a native quota dashboard and a dynamic number of persistent, isolated WebKit profiles.

## Features

- Soor/Apple Music-inspired native visual system: editorial gradients, artwork-style account identities, adaptive materials, large type, and compact one-hand navigation.
- The home screen fits all configured accounts in compact live-quota rows. Its small TIBO strip shows the latest reset-relevant public X post and an explicitly estimated probability of a reset today.
- Pull down on the overview to refresh every account quota and then reload the consolidated dashboard state.
- Compact native overview with correct remaining-quota progress bars; tap an account for full reset times and actions.
- Shows the remaining Plus/Pro subscription days from the authenticated Codex account claim, separately from quota reset times.
- Accounts are dynamic: tap `+` to create a VPS quota slot and its dedicated persistent WebKit together, authorize it inside the app, or remove both freely.
- Dynamic account count and dynamic independent ChatGPT sessions backed by persistent `WKWebsiteDataStore` identifiers.
- The authenticated VPS quota email is the account name. Account-to-WebKit mappings stay fixed; detecting a different email never silently swaps another account's WebKit.
- Optional local TIBO notifications explain the public signal, avoid duplicate alerts, and never include private account data.
- **Sign in for quota / Đăng nhập quota** starts Codex device authorization on the VPS, opens the code in the selected account's mapped WebKit, and polls until the VPS returns the authenticated email and quota. The successful snapshot is persisted immediately for subsequent dashboard loads. Local OAuth registrations alone cannot mark remote quota as connected.
- Refresh usage and consume a real reset credit from the native account screen when the Codex account exposes one.
- One global TIBO reset banner fetched by the VPS from the public OpenTheRank tracker every 15 minutes. No account data is sent to TIBO or OpenTheRank.
- Device-code entry opens `auth.openai.com/codex/device` inside the selected profile and attempts to fill the code. The user still confirms on the official OpenAI page.
- Device code is only copied to the local iPhone clipboard; the app does not upload it.
- **Code from PC** remains a separate convenience action for approving a device code generated on the user's PC. That action signs in the PC; quota in this app uses the VPS login action above.
- Per-profile clear-session action. The original five data-store UUIDs remain unchanged, so installing an update over the existing app with the same Bundle ID preserves their logins.
- Launches directly into the dashboard; the unstable startup Face ID gate is disabled.
- Face ID preference uses a namespaced key so re-signing with a reused bundle ID cannot inherit another app's lock state.
- Only one profile WebView is alive while its screen is open.
- A native Mail.tm tab creates free temporary inboxes and can map one active inbox to each Codex account and its dedicated WebKit.
- Mailboxes use a 60-day local retention target by default (or 30 days), show remaining days and unread counts, and extract likely verification codes for explicit one-tap copy.

## Temporary mail: behavior and limits

Open **Mail / Thư**, tap `+`, choose 30 or 60 days, and optionally link the new address to an existing account. The same inbox then appears in that account's detail screen beside its mapped WebKit. Pull down on the Mail list or inbox to refresh. Messages are rendered only as inert plain text; remote HTML, images, scripts, trackers, and attachment downloads are not loaded. Attachment names, types, and sizes are metadata only.

Mailbox passwords and tokens are stored in this device's Keychain with a `ThisDeviceOnly` accessibility class. Safe mailbox metadata and bounded plain-text messages are cached in Application Support for offline reading. Verification-code candidates are extracted locally and are copied only after the user taps one; the app never submits a code or automates account registration.

The 30/60-day choice is an app-managed local target, not a Mail.tm uptime guarantee. Mail.tm may remove an inactive address earlier. The app checks expiry and retries provider deletion when it next enters the foreground; offline deletion remains pending without exposing credentials. If a provider mailbox disappears early, the app can create a replacement while preserving the suggested account mapping.

This release has no push-mail guarantee, no outgoing mail, and no attachment download. New messages arrive when the app refreshes in the foreground or the user pulls to refresh. The free mail service is provided by [Mail.tm](https://mail.tm/); do not use a temporary inbox for important recovery email or long-term identity ownership.

## Generate and run

Requires macOS, Xcode with the iOS 17+ SDK, and XcodeGen:

```bash
brew install xcodegen
COCKPIT_APP_TOKEN=YOUR_PRIVATE_TOKEN python3 scripts/generate_app_auth.py
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

This private personal build receives a revocable `COCKPIT_APP_TOKEN` from the private CI secret store. It connects automatically like the original app and does not show a VPS setup screen. The token is posted in the HTTPS request body, never placed in a URL or committed to Git.

Do not publish or share the resulting personalized IPA: its embedded credential is extractable by anyone who obtains the file.

The account list is loaded dynamically and is not capped at five. Install upgrades over the existing app with the same Bundle ID and signing team. Changing the Bundle ID or deleting the app creates/removes the iOS sandbox, so WebKit cookies cannot be carried across that boundary.

After direct OAuth succeeds, the app sends only the issued OAuth credentials—not WebKit cookies or browser storage—over the authenticated Tailscale HTTPS connection for the explicitly mapped account ID. The VPS validates matching token claims, installs Codex credentials atomically, and keeps them only when Codex app-server returns a healthy live quota snapshot. A failed import restores the previous account credentials. The VPS owns subsequent token refreshes; pull-to-refresh and normal polling continue using the same quota path as older accounts.

## Cockpit Browser OAuth relay (no VPS)

Direct OAuth inside the iPhone app is now the default. Use this legacy relay only when a Cockpit PC session specifically needs to remain the OAuth client and token owner:

1. Start **Browser OAuth** in Cockpit on the PC and copy the OpenAI authorization URL it creates.
2. On the iPhone, open the matching account and choose **OAuth**. Confirm the displayed WebKit and mapped identity, then paste the URL.
3. Complete the official OpenAI page in that account's persistent WebKit. The app validates and intercepts Cockpit's loopback callback before iOS tries to open `localhost`.
4. The exact validated callback is copied locally. Paste it into Cockpit's manual callback field on the PC so Cockpit can finish the code exchange.

The PC keeps the PKCE verifier and receives the tokens; the iPhone receives neither. The app accepts only the exact OpenAI/Cockpit hosts, an HTTP loopback callback, matching port/path/state, and PKCE S256 parameters. Authorization URLs, callback URLs, codes, and state values stay in transient UI/WebKit memory and the local clipboard—they are not persisted or uploaded.

Never share an authorization or callback URL: it is short-lived authentication material. Clear the local callback after Cockpit finishes. Device-code entry remains available as a fallback from the same account card and browser menu.

## Current validation boundary

The macOS CI workflow builds the IPA and runs the Xcode unit/UI tests. Direct OAuth and device-login confirmation still happen on the official OpenAI page; third-party SSO providers may choose to redirect outside embedded web views. OpenAI's OAuth response itself does not contain numeric 5-hour/weekly quota. This personalized build therefore imports the completed login into its mapped dashboard slot and reads quota through Codex app-server, the same path used by existing accounts.

## Personalized IPA

Private CI produces an **unsigned** personalized IPA. It must be re-signed with an Apple Developer certificate or installed through a compatible sideloading service before iOS will run it. Keep the IPA private.
