# Plan cải thiện UX: Codex Cockpit iOS (bản đầy đủ, v2)

> Tài liệu giao việc cho Codex. Đây là nguồn sự thật duy nhất. Thay thế mọi bản plan trước.
> Làm **đúng thứ tự** ở mục 4. Mỗi task một commit. Báo cáo theo mẫu ở mục 9.

---

## 1. Mục tiêu

App SwiftUI (iOS 17+, XcodeGen `project.yml`) gồm dashboard quota native + nhiều profile `WKWebView` cô lập (mỗi profile một `WKWebsiteDataStore(forIdentifier:)`). Backend `server.py` trên VPS (`/opt/codex-cockpit`, service `codex-cockpit`), app gọi qua `AppURLs.base` (Tailscale).

| Chỉ số | Trước | Mục tiêu |
|---|---|---|
| Thao tác từ mở app → code nằm trong ô OpenAI | 6–7 tap + gõ | ≤ 2 tap (dán / quick action / link) |
| Xác nhận code → code điền xong (profile warm) | 2–6 s, hay fail | < 1 s, điền thành công ~100% |
| "Ủy quyền lại" → thấy trang OpenAI | chờ VPS tới 15 s | tức thì, code tự điền khi về |
| Mở app → thấy quota | chờ VPS (tới 35 s) | tức thì (cache), refresh nền |
| WebKit nhớ đăng nhập ChatGPT | chỉ cookie | cookie + Keychain tự điền email/mật khẩu |

---

## 2. Quyền hạn & quy tắc làm việc

### 2.1 Git & push (chủ repo HNam1234 đã cho phép, tự chịu trách nhiệm)
- Repo: `https://github.com/HNam1234/codex-cockpit-ios`. Làm trên branch `ux/fast-device-code`.
- **Được push trực tiếp lên `main`** tại mỗi MỐC (mục 4):
  ```bash
  git fetch origin
  git rebase origin/main          # chỉ khi main có commit mới
  python scripts/verify_project.py
  git push origin ux/fast-device-code
  git push origin ux/fast-device-code:main
  ```
- **Cấm**: force-push, viết lại lịch sử `main`, xoá branch của người khác, commit `ops/`, `tmp/`, `work/`.
- Commit message dạng conventional (`feat:`, `fix:`, `fix(ci):`, `test:`, `docs:`, `chore:`).

### 2.2 Đăng nhập GitHub
- Chủ repo cho phép Codex đăng nhập GitHub và dùng repo này.
- Kiểm tra: `gh auth status`. Đã đăng nhập (account HNam1234) → dùng luôn.
- Chưa đăng nhập:
  ```bash
  gh auth login --hostname github.com --git-protocol https --web
  gh auth setup-git
  ```
  Lệnh in ra mã một lần + link `github.com/login/device`. **Báo mã cho chủ repo** để họ xác nhận trên trình duyệt, chờ họ xác nhận rồi làm tiếp.
- **Không** tự nhập mật khẩu/token vào đâu cả. Không ghi token vào file, không commit token.
- Được dùng `gh` cho: `run list/watch/view/rerun`, `workflow run`, `run download` (tải IPA).
- **Không** sửa settings repo, secrets, variables, branch protection, collaborators, webhooks, Actions permissions.

### 2.3 CI
- `Build unsigned IPA` (`.github/workflows/build-unsigned-ipa.yml`) **tự chạy khi push `main`**: XcodeGen → unit + UI test trên simulator → build IPA.
- `Build signed IPA` chỉ chạy tay. Được phép chạy ở cuối mỗi MỐC:
  ```bash
  gh workflow run build-signed-ipa.yml -R HNam1234/codex-cockpit-ios -f export_method=ad-hoc
  ```
- Theo dõi:
  ```bash
  gh run list -R HNam1234/codex-cockpit-ios -L 5
  gh run watch <run-id> -R HNam1234/codex-cockpit-ios --exit-status
  gh run view <run-id> -R HNam1234/codex-cockpit-ios --log-failed
  ```
- **CI đỏ** → sửa ngay (`fix(ci): ...`), push lại. **Không làm task mới khi `main` đang đỏ.**
- Cùng một lỗi sửa 3 lần vẫn đỏ → **dừng**, báo log lỗi + giả thuyết cho chủ repo.
- Máy local là Windows, không có Xcode: chỉ chạy được `python scripts/verify_project.py`, `git diff --check`, kiểm tra cú pháp JS bằng Node. Mọi lỗi Swift chỉ lộ ra trên CI, nên viết Swift cẩn thận, đúng API iOS 17 (API mới hơn phải bọc `if #available`).

### 2.4 VPS
- `/opt/codex-cockpit/server.py` **không nằm trong git**. **Chưa được phép sửa.** Task 11 phải hỏi chủ repo trước.

---

## 3. Ràng buộc kỹ thuật (KHÔNG vi phạm)

1. **Không đổi** `WebProfile.persistentIdentifier(for:)`, 5 UUID gốc, bundle ID `vn.nam.CodexCockpit`. Đổi = user mất cookie đăng nhập WebKit.
2. **Không** gửi device code, email, mật khẩu, cookie lên VPS hay host nào ngoài trang OpenAI đang mở trong WebView.
3. **Không** tự bấm nút cấp quyền cuối (Authorize/Allow) trên OpenAI. Chỉ được tự submit **bước nhập code** khi user bật tùy chọn (mặc định TẮT). **Không** tự bấm Login/Continue ở bước đăng nhập.
4. `scripts/verify_project.py` phải pass trước mỗi commit. Lưu ý:
   - Cấm chuỗi `password =` trong mọi file Swift → đặt tên `secret`, `passphrase`, `credentialSecret`.
   - Script WebKit cấm `document.cookie`, `localStorage`, `sessionStorage`.
   - Giữ mọi chuỗi mà verifier assert (`openDeviceLogin`, `WKWebsiteDataStore(forIdentifier:`, `.refreshable`, `await store.refreshAll()`, `scenePhase == .active`, `identityScanner.scan`, `onIdentityDetected`, `.defaultClient`...).
5. File Swift mới trong `CodexCockpit/` tự vào target. Key Info.plist dùng `INFOPLIST_KEY_*`. Riêng `CFBundleURLTypes` dùng khối `info:` trong `project.yml`.
6. UI tiếng Việt, dùng design system sẵn có (`DesignSystem.swift`: `glassCard`, `CockpitTheme`, `SectionHeading`, `CapsuleActionStyle`, `ProfileArtwork`).
7. Tái sử dụng code đã có, không viết lại: `WebIdentityScanner`/`WebIdentityBridge` (nhận diện tài khoản), `CockpitCredentialStore` (pattern Keychain), `store.refreshAll()` + refresh theo `scenePhase` trong `RootView`, `CockpitStore.startPolling`.

---

## 4. Lộ trình & trạng thái

| # | Việc | Trạng thái |
|---|---|---|
| 1 | `DeviceCode` model/formatter + test | ✅ `d3ea814`, `0f0cc36` |
| 2 | `DeviceCodeAutofill` (user script, MutationObserver, OTP nhiều ô) | ✅ `674c687`, `16f64c9` |
| 3 | `WebViewPool` giữ ấm 2 WebView | ✅ `d84f470`, **có lỗi → Bước 0** |
| **0** | **Sửa lỗi pool** | ⏳ làm ngay |
| — | **MỐC 1**: push main, CI xanh, signed IPA, chủ repo thử trên iPhone | |
| 4 | Lối vào nhanh: nút nổi, Quick Action, URL scheme, App Shortcut, chip clipboard | |
| 5 | `DeviceCodeSheet` mới | |
| 6 | "Ủy quyền lại" song song + banner + tự quay về | |
| 7 | Cài đặt device code | |
| — | **MỐC 2** | |
| 8a | Badge trạng thái đăng nhập từng profile | |
| 8b | `CredentialVault` (Keychain + Face ID) | |
| 8c | Tự điền email/mật khẩu trên `auth.openai.com` | |
| — | **MỐC 3** | |
| 9 | Cache snapshot, khởi động tức thì | |
| 10 | Giảm giật, toast, skeleton, haptics | |
| 12 | Test, đo, verifier, version, README | |
| — | **MỐC 4** | |
| 11 | Server VPS: trả `start_login` sớm | ⛔ chờ chủ repo cho phép |

---

## 5. Bước 0: sửa lỗi `WebViewPool` (bắt buộc trước mọi việc khác)

**Lỗi:** `BrowserState.attach` chỉ mở `initialRequest` khi `webView.url == nil`. WebView trong pool đang ở `chatgpt.com` → vào bằng "Ủy quyền lại" vẫn hiện ChatGPT; `onAppear` chỉ set `pendingDeviceCode` nên code không được điền và trang device không mở. Ngược lại "Mở Web" khi WebView đang ở trang device thì vẫn hiện trang device. Thêm nữa: `prewarmDeviceProfile()` chạy mỗi lần `store.accounts` đổi và có thể kéo một WebView đang mở ChatGPT dở sang trang device.

**Sửa:**
1. Thêm hàm thuần trong `WebViewPool`:
   ```swift
   enum NavigationDecision: Equatable { case keep, load, reload }
   nonisolated static func shouldNavigate(current: URL?, requested: URL, lastFinishedAt: Date?, now: Date) -> NavigationDecision
   ```
   - `current` nil / `about:blank` → `.load`
   - host/path của `current` khác `requested` → `.load`
   - cùng trang device, `lastFinishedAt` < 10 phút → `.keep`; ≥ 10 phút hoặc nil → `.reload`
   - cùng trang khác (ví dụ ChatGPT) → `.keep`
2. `WebViewPool.attach`: khi gắn vào container mới, dùng `shouldNavigate` với `initialRequest.url` để quyết định load/reload/keep.
3. `AccountBrowserView.onAppear` với `launch.mode == .device`: gọi `browser.openDeviceLogin(code:)` (hàm này tự xử lý khi trang device đã sẵn). Bỏ việc chỉ set `pendingDeviceCode`.
4. `WebViewPool.prewarm`: chỉ điều hướng khi entry **vừa được tạo**, hoặc URL hiện tại là nil / `about:blank` / `/codex/device` (reload nếu cũ). **Không bao giờ** điều hướng WebView đang ở trang khác.
5. Unit test `CodexCockpitTests/WebViewPoolDecisionTests.swift`: ChatGPT→device = `.load`; device→ChatGPT = `.load`; device mới→device = `.keep`; device 11 phút→device = `.reload`; nil→device = `.load`; ChatGPT→ChatGPT = `.keep`.
6. Commit: `fix: honor requested page when reusing pooled webviews`.

### MỐC 1
Push main (mục 2.1). Đây là **lần build đầu tiên** của 7 commit, nhiều khả năng có lỗi compile, sửa đến khi xanh. Chạy signed IPA. Báo chủ repo thử trên iPhone:
- (a) Account → "Ủy quyền lại" → trang OpenAI mở → code tự điền, chip "Đã điền code ✓".
- (b) "Mở Web" → ChatGPT; quay lại → "Ủy quyền lại" → vẫn ra trang device.
- (c) Ra vào màn web nhiều lần không bị tải lại trang.

---

## 6. Giai đoạn P0: device code tức thì

### Task 4: Lối vào nhanh
1. **Router** (`AppRouter` trong `Models/AccountProfile.swift`):
   - `struct DeviceCodeRequest: Identifiable, Equatable { let id = UUID(); var code: DeviceCode?; var accountID: String? }`
   - `@Published var deviceCodeRequest: DeviceCodeRequest?`
   - `func presentDeviceCode(code: DeviceCode? = nil, accountID: String? = nil)`
   - `RootView`: `.sheet(item: $router.deviceCodeRequest)` ở **cấp gốc** → mở được từ mọi tab.
2. **Nút nổi** trên `CockpitView`: capsule lớn "Nhập device code" (`key.horizontal.fill`) ở `safeAreaInset(edge: .bottom)` phía trên tab bar, luôn hiện. `accessibilityIdentifier("device-code-fab")`.
3. **Home Screen Quick Action**: dynamic shortcut `vn.nam.CodexCockpit.deviceCode` "Nhập device code" (set trong `sceneDidBecomeActive`/khi app start). Cần `@UIApplicationDelegateAdaptor` + `UISceneConfiguration` trỏ `SceneDelegate` để nhận `windowScene(_:performActionFor:completionHandler:)` (warm) và `connectionOptions.shortcutItem` (cold). Chuyển vào router qua `@MainActor final class DeepLinkInbox: ObservableObject` (singleton) mà `RootView` quan sát.
4. **URL scheme** `codexcockpit://device?code=ABCD-EFGHI&account=<id>` (cả hai tham số tùy chọn). `project.yml` target `CodexCockpit`:
   ```yaml
   info:
     path: CodexCockpit/Info.plist
     properties:
       CFBundleURLTypes:
         - CFBundleURLName: vn.nam.CodexCockpit
           CFBundleURLSchemes: [codexcockpit]
   ```
   Giữ `GENERATE_INFOPLIST_FILE: true`. Commit `Info.plist` nếu XcodeGen yêu cầu file tồn tại. Xử lý bằng `.onOpenURL` trong `RootView`. Parser thuần `enum DeepLink { static func parse(_ url: URL) -> DeviceCodeRequest? }` + test `DeepLinkTests` (code hợp lệ, code rác → request không code, scheme/host sai → nil, account id có ký tự đặc biệt).
5. **App Shortcut** (`AppIntents`): `OpenDeviceCodeIntent` (`@Parameter code: String?`, `openAppWhenRun = true`) → đẩy vào `DeepLinkInbox`. `AppShortcutsProvider` phrase: "Nhập device code trong \(.applicationName)".
6. **Chip clipboard**: khi vào foreground, nếu `UIPasteboard.general.hasStrings` và `changeCount` khác lần đã thấy → chip "Dán device code từ clipboard" ở đầu `CockpitView`. **Không** tự đọc `UIPasteboard.general.string` (sẽ bật banner "đã dán từ…"). Bấm chip mới đọc → `DeviceCode.extract` → mở sheet điền sẵn; không tìm thấy code → toast "Clipboard không có device code".

Commit: `feat: add fast entry points for device code`.

### Task 5: `DeviceCodeSheet` mới
File riêng `CodexCockpit/Views/DeviceCodeSheet.swift`, dùng cho mọi lối vào (thay bản private trong `ProfileDetailView.swift`).
- Ô nhập lớn monospaced, `@FocusState` → **bàn phím bật ngay**; `.textContentType(.oneTimeCode)`, `.keyboardType(.asciiCapable)`, `.textInputAutocapitalization(.characters)`, `.autocorrectionDisabled()`, `.submitLabel(.go)`.
- Format khi gõ bằng `DeviceCode.normalize`.
- `PasteButton(payloadType: String.self)` → `DeviceCode.extract`.
- **Chip chọn profile** (scroll ngang): `ProfileArtwork` nhỏ + identity/tên account. Mặc định: `request.accountID` → profile đó; không có → `CodexCockpit.lastDeviceProfile.v1`; không có → profile của account đầu tiên lỗi auth; không có → account đầu tiên. Đổi chip → `WebViewPool.shared.prewarm(profile:)`.
- **Tự đi tiếp**: `DeviceCode.parse` thành công → haptic `.success` → chờ 250 ms → `open`. Vẫn có nút "Mở OpenAI".
- `open`: copy code đã normalize vào clipboard, lưu `lastDeviceProfile`, đóng sheet, điều hướng `.browser(accountID, BrowserLaunch(mode: .device, code: ...))` trên tab Tổng quan (chuyển tab nếu cần). Nếu đang đứng ở `AccountBrowserView` đúng account → không push thêm, chỉ `browser.openDeviceLogin(code:)`.
- `.presentationDetents([.height(380), .medium])`, `.presentationDragIndicator(.visible)`.
- Identifiers: `device-code-field`, `device-code-open`, `device-code-profile-<id>`.

Commit: `feat: redesign device code sheet for one-step entry`.

### Task 6: "Ủy quyền lại" song song
1. `AccountDetailView` nút "Ủy quyền lại": **điều hướng ngay** tới `.browser(accountID, BrowserLaunch(mode: .device, code: nil, verificationURL: nil))`, đồng thời `Task { await store.beginReauthorization(accountID:) }`.
2. `AccountBrowserView` quan sát `store.loginSessions[accountID]`: khi `userCode` xuất hiện → `browser.openDeviceLogin(code:)`.
3. `DeviceAuthBanner` dính đầu web view (chỉ ở mode device): code lớn + nút copy + trạng thái: "Đang lấy code…" / "Đã điền — bấm Continue rồi Authorize" / "Hoàn tất ✓" / lỗi + nút "Thử lại".
4. `CockpitStore.startPolling`: 0.5 s khi `status == "creating"` hoặc chưa có `userCode`; 2 s khi `waiting`; dừng khi `succeeded`/`failed`/quá `expiresAt`/app background > 15 phút. `beginReauthorization` phải chấp nhận response `creating` chưa có code.
5. `succeeded` → haptic `.success`, banner "Hoàn tất ✓", sau 1.2 s tự pop về `AccountDetailView` (chỉ khi top của `cockpitPath` là browser của đúng account); quota đã được `replace`.

Commit: `feat: run reauthorization in parallel with the device page`.

### Task 7: Cài đặt
`SettingsView` section "Device code":
- "Tự gửi code sau khi điền": `@AppStorage("CodexCockpit.autoSubmitCode.v1")`, mặc định **false**. Mô tả: "Chỉ gửi bước nhập code. Bước cấp quyền bạn vẫn tự bấm."
- "Giữ ấm trang đăng nhập": `@AppStorage("CodexCockpit.prewarm.v1")`, mặc định **true**. Tắt → `WebViewPool` không prewarm và evict các entry không hiển thị.

Commit: `feat: add device code settings`.

### MỐC 2
Push main, CI xanh, signed IPA. Chủ repo thử: Quick Action, `codexcockpit://device?code=TEST-12345` từ Notes/Safari, nút nổi, dán code, "Ủy quyền lại" (mở ngay, tự điền, tự quay về).

---

## 7. Giai đoạn P1: WebKit nhớ tài khoản ChatGPT

### Task 8a: Trạng thái đăng nhập từng profile
- Dùng lại `WebIdentityScanner`/`WebIdentityBridge` (`/api/auth/session`) để xác định profile có phiên ChatGPT hợp lệ. Không đọc cookie bằng JS.
- `AccountsView` + card WebKit trong `AccountDetailView`: badge "Đã đăng nhập" (xanh) / "Cần đăng nhập" (cam) / "Đang kiểm tra" (xám).
- Commit: `feat: show chatgpt sign-in state per profile`.

### Task 8b: `CredentialVault`
File `CodexCockpit/Services/CredentialVault.swift`, theo pattern `CockpitCredentialStore`.
- `protocol CredentialStoring` + `KeychainCredentialStore` + `InMemoryCredentialStore` (cho test).
- Service riêng `vn.nam.CodexCockpit.chatgpt`, `kSecAttrAccount = profile.id`.
- **Email**: item riêng, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, đọc không cần Face ID.
- **Mật khẩu**: item riêng, `SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil)`. Đọc bằng một `LAContext` có `touchIDAuthenticationAllowableReuseDuration = 300`.
- Không `kSecAttrSynchronizable`. Không backup iCloud. Không gửi đi đâu.
- UI: card WebKit → "Tài khoản ChatGPT đã lưu" (email, nút Sửa / Xoá). Form native: `TextField` `.textContentType(.username)`, `SecureField` `.textContentType(.password)` để iOS cho AutoFill từ iCloud Keychain / 1Password vào form của app.
- "Xoá session" **không** xoá vault; vault có nút xoá riêng.
- Verifier: assert `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` và `.userPresence` có trong file; `kSecAttrSynchronizable` không có.
- Test: lưu / đọc / xoá / ghi đè bằng `InMemoryCredentialStore`.
- Commit: `feat: add keychain vault for chatgpt credentials`.

### Task 8c: Tự điền đăng nhập OpenAI
- User script thứ hai (`.atDocumentEnd`, `.defaultClient`, main frame): chỉ khi `location.host === 'auth.openai.com'`. Theo dõi (MutationObserver) sự xuất hiện của ô email (`input[type=email]`, `input[name=email]`, `input[autocomplete=username]`) hoặc ô mật khẩu (`input[type=password]`) đang hiển thị. Script **không chứa dữ liệu**. Chỉ `postMessage({type:'loginFieldVisible', field:'email'|'password'})`.
- Native (handler riêng, cùng weak proxy): kiểm tra `message.webView?.url?.host == "auth.openai.com"` → đọc vault → `evaluateJavaScript("__cockpitFillLogin(field, value)", in: nil, in: .defaultClient)` với giá trị JSON-encode. Setter gốc + `input`/`change`.
- **Không** tự bấm Continue/Login. Thanh nhỏ dưới web view: "Đã điền email ✓, bấm Continue" / "Đã điền mật khẩu ✓".
- Mật khẩu cần Face ID; user huỷ → không điền, hiện nút "Điền mật khẩu".
- Trang chọn Google/Apple/Microsoft → không làm gì. UI vault ghi chú: "Đăng nhập Google có thể bị Google chặn trong WebView nhúng; khi đó chỉ cookie được giữ."
- README: mật khẩu chỉ nằm trong Keychain thiết bị, không đồng bộ, không gửi VPS.
- Commit: `feat: autofill saved chatgpt credentials on openai login`.

### MỐC 3
Push main, CI xanh, signed IPA. Chủ repo thử: lưu tài khoản cho 1 profile → "Xoá session" profile đó → mở Web → email tự điền → Continue → Face ID → mật khẩu tự điền.

---

## 8. Giai đoạn P2: mượt & nhanh

### Task 9: Cache snapshot
- `CockpitAPI.status()` trả kèm raw `Data`. `SnapshotCache` ghi atomic `Application Support/status-cache.json` (`.completeFileProtectionUntilFirstUserAuthentication`).
- `CockpitStore.init` nạp cache đồng bộ → `accounts` có ngay. `load()`/`refreshAll()` refresh nền.
- Header: "Cập nhật lúc HH:mm"; chấm vàng nếu cache > 5 phút.
- Dùng lại refresh theo `scenePhase == .active` sẵn có; chỉ refresh nếu dữ liệu > 60 s.
- Test `SnapshotCacheTests` (ghi/đọc, file hỏng → bỏ qua).
- Commit: `feat: show cached quota instantly on launch`.

### Task 10: Giảm giật
- Thay `.alert` lỗi ở `CockpitView` bằng `ErrorToast` inline tự ẩn sau 4 s.
- `BrowserState.update`: chỉ gán khi giá trị đổi; `progress` làm tròn 0.05, ≤ 10 lần/s.
- `MiniQuotaRow`/`QuotaProgressRow`: bỏ `GeometryReader`, dùng `Capsule().fill(color).scaleEffect(x: ratio, anchor: .leading)` trên capsule nền.
- `AccountOverviewCard`: giảm/bỏ shadow; `.compositingGroup()` nếu cần.
- Skeleton `.redacted(reason: .placeholder)` khi chưa có cache.
- Haptics: refresh xong `.light`, reset credit thành công `.success`, lỗi `.error`.
- `URLSession` riêng timeout 15 s cho `app-status`/`app-refresh`; giữ 35 s cho `app-auth/start`.
- Commit: `perf: smooth dashboard rendering and feedback`.

### Task 12: Test, đo, hoàn thiện
- Unit test còn thiếu: `DeepLinkTests`, `CredentialVaultTests`, `SnapshotCacheTests`, `WebViewPoolDecisionTests` (nếu chưa).
- UI test `UITEST_MODE=device-sheet`: `RootView` không gọi VPS, nạp 2 account giả, WebView trỏ `about:blank`. Kịch bản: tap `device-code-fab` → field có focus → gõ `abcd12345` → hiển thị `ABCD-12345` → màn browser xuất hiện.
- UI test mở bằng URL: `app.open(URL(string: "codexcockpit://device?code=ABCD-12345")!)` (bọc `if #available(iOS 16.4, *)`) → sheet có code điền sẵn.
- `OSSignposter` (subsystem `vn.nam.CodexCockpit`, category `DeviceCode`): interval "sheet open → codeFilled"; log DEBUG.
- Verifier: assert tồn tại `DeviceCodeAutofill.swift`, `WebViewPool.swift`, `DeviceCodeSheet.swift`, `CredentialVault.swift`, và `codexcockpit` trong `project.yml`.
- `project.yml`: `MARKETING_VERSION` → `1.4.0`, `CURRENT_PROJECT_VERSION` +1.
- README: cập nhật tính năng (pool 2 WebView, lối vào nhanh, vault, cache).
- Commit: `test: cover fast device code flow` và `chore: release 1.4.0`.

### MỐC 4
Push main, CI xanh, signed IPA, báo chủ repo bản 1.4.0.

### Task 11: Server VPS (⛔ chỉ khi chủ repo cho phép)
- Backup: `cp /opt/codex-cockpit/server.py /opt/codex-cockpit/server.py.bak-$(date +%Y%m%d-%H%M%S)`.
- `start_login`: `session["ready"].wait(timeout=15)` → `timeout=2`, trả `status: "creating"` sớm (app Task 6 đã poll 0.5 s).
- Kiểm tra: `python3 -m py_compile server.py`; `python3 smoke_device_login.py`; `systemctl restart codex-cockpit && systemctl is-active codex-cockpit`; gọi `app-status` qua `127.0.0.1:8787`.
- Lỗi → chép lại backup, restart.

---

## 9. Mẫu báo cáo sau mỗi MỐC

```
MỐC n: <tên>
- Commits: <hash> <message> (liệt kê)
- Push: main = <hash>
- CI unsigned: <link run> → ✅/❌ (số lần sửa)
- Signed IPA: <link run> → ✅/❌
- Chủ repo cần thử trên iPhone: <danh sách bước>
- Rủi ro / việc còn treo: <...>
```

Dừng lại chờ chủ repo khi: cần xác nhận mã `gh auth login`; cùng một lỗi CI sửa 3 lần vẫn đỏ; trước Task 11; hoặc phát hiện việc cần vi phạm mục 3.
