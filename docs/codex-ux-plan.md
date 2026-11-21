# Plan cải thiện UX — Codex Cockpit iOS

> Tài liệu giao việc cho Codex. Làm **theo thứ tự task**, mỗi task một commit trên branch `ux/fast-device-code`. Không push khi chưa được user đồng ý.

## 0. Bối cảnh & mục tiêu

App SwiftUI (iOS 17+, XcodeGen `project.yml`) gồm dashboard quota native + nhiều profile `WKWebView` cô lập (mỗi profile 1 `WKWebsiteDataStore(forIdentifier:)`). Backend: `server.py` trên VPS (`/opt/codex-cockpit`, service `codex-cockpit`), app gọi qua `AppURLs.base` (Tailscale).

**Mục tiêu đo được**

| Chỉ số | Hiện tại | Mục tiêu |
|---|---|---|
| Thao tác từ mở app → code đã nằm trong ô OpenAI | 6–7 tap + gõ | ≤ 2 tap (dán/quick action) |
| Thời gian từ xác nhận code → code điền xong (profile đã warm) | 2–6 s, hay fail | < 1 s, tỉ lệ điền thành công ~100% |
| Mở app → thấy quota | chờ VPS (tới 35 s) | tức thì (cache), refresh nền |
| WebKit nhớ đăng nhập ChatGPT | chỉ cookie | cookie + kho tài khoản/mật khẩu Keychain tự điền |

**Vấn đề gốc đã xác định**

1. `ProfileWebView` tạo `WKWebView` mới mỗi lần mở, huỷ khi rời màn → cold start + tải lại trang.
2. Điền code chỉ chạy 1 lần ở `didFinish` (`ProfileWebView.swift`), nhưng trang OpenAI là SPA → input thường chưa tồn tại → fail im lặng. Selector `input[type="text"]` quá rộng, không hỗ trợ OTP nhiều ô.
3. Nhập code thủ công bị chôn sâu: Home → Account → Mở Web → 🔑 → sheet.
4. "Ủy quyền lại" tuần tự: chờ `app-auth/start` (server có thể giữ request tới 15 s) rồi mới mở web.
5. Không cache snapshot → màn hình trống lúc khởi động; lỗi refresh bật `alert` chặn màn hình.
6. `BrowserState` publish `estimatedProgress` liên tục → re-render cả `AccountBrowserView`.

## 1. Ràng buộc bắt buộc (KHÔNG được vi phạm)

- **Không đổi** `WebProfile.persistentIdentifier(for:)`, 5 UUID gốc, bundle ID `vn.nam.CodexCockpit`. Đổi = mất cookie đăng nhập của user.
- **Không** gửi device code, email, mật khẩu, cookie lên VPS hay bất kỳ host nào ngoài trang OpenAI đang mở trong WebView.
- **Không** tự bấm nút cuối cùng "Authorize/Allow/Continue" trên trang xác nhận quyền của OpenAI; user tự xác nhận. Chỉ được tự submit bước *nhập code* nếu user bật tùy chọn (mặc định TẮT).
- `scripts/verify_project.py` phải pass. Lưu ý: nó cấm chuỗi `password =` trong mọi file Swift → đặt tên biến kiểu `secret`, `passphrase`, `credentialSecret`. Giữ nguyên các chuỗi nó kiểm tra (`openDeviceLogin`, `WKWebsiteDataStore(forIdentifier:`, `auth.openai.com/codex/device`, ...).
- Không có Mac trên máy local: không chạy được `xcodebuild`. Kiểm tra local bằng `python scripts/verify_project.py`; build + unit/UI test chạy trên CI macOS (`.github/workflows/build-unsigned-ipa.yml`). Viết code Swift cẩn thận, tránh API > iOS 17 (hoặc bọc `if #available`).
- File Swift mới đặt trong `CodexCockpit/` sẽ tự vào target (XcodeGen `sources: path`). Key Info.plist: dùng `INFOPLIST_KEY_*` nếu có; `CFBundleURLTypes` thì thêm khối `info:` trong `project.yml` (xem Task 4).
- UI text tiếng Việt, giữ design system hiện có (`DesignSystem.swift`: `glassCard`, `CockpitTheme`, `SectionHeading`, `CapsuleActionStyle`).

---

## Giai đoạn P0 — Device code tức thì

### Task 1 — `DeviceCode` model + formatter (thuần logic, có unit test)

File mới: `CodexCockpit/Models/DeviceCode.swift`

```swift
struct DeviceCode: Hashable {
    let value: String            // dạng chuẩn "ABCD-EFGHI"
    static func normalize(_ raw: String) -> String   // uppercase, bỏ khoảng trắng/ký tự lạ, giữ A-Z0-9, tự chèn "-" sau 4 ký tự
    static func parse(_ raw: String) -> DeviceCode?  // trả nil nếu không khớp
    static func extract(from text: String) -> DeviceCode? // tìm code trong đoạn text dài (clipboard chứa cả câu)
}
```

- Regex chấp nhận: `^[A-Z0-9]{4}-?[A-Z0-9]{4,5}$` sau normalize. Đặt pattern thành `static let` để dễ chỉnh.
- Loại bỏ ký tự dễ nhầm do người gõ? **Không** — không tự sửa O/0, chỉ normalize.
- Unit test `CodexCockpitTests/DeviceCodeTests.swift`: `"abcd efghi"`, `"ABCD-EFGH"`, `"Your code: WXYZ-12345."`, chuỗi rác → nil, chuỗi 3 ký tự → nil, input có dấu gạch dưới/emoji.

**Done khi:** test pass trên CI, `BrowserState.openDeviceLogin` và `DeviceCodeSheet` dùng `DeviceCode.normalize` thay cho filter inline hiện tại.

### Task 2 — Script điền code bền vững (`DeviceCodeAutofill`)

File mới: `CodexCockpit/Web/DeviceCodeAutofill.swift`

1. Tạo JS một lần (string tĩnh), cài bằng `WKUserScript(injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)` vào `userContentController` của **mọi** profile WebView. Script định nghĩa `window.__cockpitFillCode(code)`:
   - Chỉ hoạt động khi `location.host === "auth.openai.com"` và path bắt đầu `/codex/device` (kiểm tra cả trong JS lẫn native).
   - Tìm input theo thứ tự ưu tiên: `input[autocomplete="one-time-code"]` → `input[name*="code" i]`, `input[id*="code" i]` → `input[inputmode="text"]` duy nhất hiển thị trong `form`. Không dùng `input[type="text"]` trần nếu có nhiều hơn 1.
   - Nếu có **nhiều ô 1 ký tự** (`maxlength="1"`, ≥ 6 ô) → điền từng ký tự (bỏ dấu `-`) vào từng ô.
   - Set value bằng setter gốc `HTMLInputElement.prototype` + dispatch `input`, `change`; focus ô.
   - Nếu chưa thấy input: dùng `MutationObserver` trên `document.body` + timeout 8 s; điền ngay khi input xuất hiện.
   - Trả kết quả về native qua `window.webkit.messageHandlers.cockpitAutofill.postMessage({type:"codeFilled"|"codeNotFound"})`.
   - Nếu user bật "Tự gửi code" (Task 7): sau khi điền, click nút submit **của form chứa input** (`form.requestSubmit()` hoặc button `type=submit` trong form đó). Không click gì khác.
2. Native: `DeviceCodeAutofill.fill(code:in:)` gọi `evaluateJavaScript` với code được **JSON-encode** (`JSONSerialization`/`JSONEncoder` → literal string) thay vì escape thủ công như hiện tại.
3. Gọi `fill` ở cả hai thời điểm: ngay khi `pendingDeviceCode` được set mà trang device đã load sẵn (trường hợp WebView warm), và ở `didFinish` (trường hợp cold). Idempotent: chỉ clear `pendingDeviceCode` khi nhận `codeFilled`.
4. Xoá logic điền cũ trong `ProfileWebView.Coordinator.webView(_:didFinish:)`.
5. `BrowserState` thêm `@Published var autofillStatus: AutofillStatus` (`.idle/.waiting/.filled/.notFound`) để UI hiện chip "Đã điền code ✓" hoặc "Không tìm thấy ô — đã copy code, hãy dán".

**Done khi:** luồng cũ vẫn chạy; khi trang render chậm vẫn điền được; message handler gỡ trong `dismantle`/khi trả về pool (tránh retain cycle — dùng một proxy `WeakScriptMessageHandler`).

### Task 3 — `WebViewPool`: WebView giữ ấm, mở tức thì

File mới: `CodexCockpit/Web/WebViewPool.swift`

- `@MainActor final class WebViewPool` singleton. Mỗi entry: `profileID`, `WKWebView`, `BrowserState`, `lastUsed`.
- `func webView(for profile: WebProfile) -> (WKWebView, BrowserState)`: lấy từ pool hoặc tạo mới (config như `makeUIView` hiện tại + user script Task 2 + message handler).
- `func prewarm(profile: WebProfile, url: URL)`: tạo (nếu chưa có) và load URL ở nền, **không** gắn vào view hierarchy. Mặc định prewarm `AppURLs.deviceLogin`.
- Giới hạn **2 entry** (LRU). Evict khi `UIApplication.didReceiveMemoryWarningNotification` (giữ lại entry đang hiển thị). Xử lý `webViewWebContentProcessDidTerminate` → reload.
- `ProfileWebView` đổi thành: `makeUIView` trả về một `UIView` container, gắn webView từ pool vào làm subview (autoresizing full). `dismantleUIView` chỉ **gỡ** webView khỏi container và trả về pool, không `stopLoading`, không nil delegate.
- `AccountBrowserView` dùng `BrowserState` từ pool thay vì `@StateObject` mới (truyền qua `@ObservedObject`).
- "Xoá session" (`ProfileDataStore.clear`): phải gọi `WebViewPool.shared.evict(profileID:)` **trước** khi remove data store (WebKit yêu cầu không còn WebView nào dùng store).
- Khi nào prewarm:
  - Sau `store.load()` thành công lần đầu: prewarm profile "dùng gần nhất cho device code" (lưu `UserDefaults` key `CodexCockpit.lastDeviceProfile.v1`; fallback profile của account đầu tiên có lỗi auth, rồi account đầu tiên).
  - Khi app vào foreground (`scenePhase == .active`) nếu entry đã bị evict.
  - Khi mở `DeviceCodeSheet` (Task 5) và user đổi chip profile → prewarm profile đó ngay.
- Nếu trang warm đã ở `/codex/device` và load xong → mở chỉ cần gắn view + điền code (không reload). Nếu đã quá 10 phút kể từ lần load → reload trước khi điền (tránh CSRF/session của trang cũ hết hạn).
- Cập nhật README (bỏ dòng "Only one profile WebView is alive...", thay bằng "Tối đa 2 WebView được giữ ấm").

**Done khi:** quay lại màn web không tải lại trang; mở device-login cho profile đã warm hiển thị ngay trang có sẵn; xoá session vẫn hoạt động.

### Task 4 — Lối vào nhanh: nút nổi, Quick Action, URL scheme, App Shortcut

1. **Router**: thêm vào `AppRouter`:
   - `@Published var deviceCodeRequest: DeviceCodeRequest?` (`struct { var code: DeviceCode?; var accountID: String? }`, `Identifiable`).
   - `func presentDeviceCode(code: DeviceCode? = nil, accountID: String? = nil)`.
   - `RootView` gắn `.sheet(item: $router.deviceCodeRequest)` ở **cấp gốc** → mở được từ mọi tab.
2. **Nút nổi** trên `CockpitView`: nút capsule lớn "Nhập device code" (icon `key.horizontal.fill`) đặt `safeAreaInset(edge: .bottom)` phía trên tab bar, luôn hiện. Thêm `accessibilityIdentifier("device-code-fab")`.
3. **Home Screen Quick Action** (nhấn giữ icon): dynamic shortcut item `vn.nam.CodexCockpit.deviceCode` – "Nhập device code". Cần `AppDelegate` qua `@UIApplicationDelegateAdaptor` + `UISceneConfiguration` với `SceneDelegate` để nhận `windowScene(_:performActionFor:)` và `connectionOptions.shortcutItem` (cold launch). Chuyển tiếp vào router qua `NotificationCenter` hoặc một `@MainActor` shared `DeepLinkInbox`.
4. **URL scheme** `codexcockpit://device?code=ABCD-EFGHI&account=<id>` (cả hai tham số tùy chọn). Thêm vào `project.yml` target `CodexCockpit`:
   ```yaml
   info:
     path: CodexCockpit/Info.plist
     properties:
       CFBundleURLTypes:
         - CFBundleURLName: vn.nam.CodexCockpit
           CFBundleURLSchemes: [codexcockpit]
   ```
   (giữ `GENERATE_INFOPLIST_FILE: true`; XcodeGen sẽ merge. Commit file `Info.plist` sinh ra nếu cần.) Xử lý bằng `.onOpenURL` trong `RootView`. Parser thuần logic `DeepLink.parse(URL) -> DeviceCodeRequest?` + unit test.
5. **App Shortcut** (`AppIntents`, iOS 16+): `OpenDeviceCodeIntent` (tham số `code: String?` tùy chọn, `openAppWhenRun = true`) + `AppShortcutsProvider` với phrase "Nhập device code trong \(.applicationName)". Intent đẩy request vào `DeepLinkInbox`.
6. **Gợi ý clipboard khi vào foreground**: nếu `UIPasteboard.general.hasStrings == true` và `changeCount` khác lần đã thấy (lưu trong bộ nhớ) → hiện chip nhỏ "Dán device code từ clipboard" ở đầu `CockpitView`. **Không** đọc `UIPasteboard.general.string` tự động (sẽ bật banner "Codex Cockpit đã dán từ…"); chỉ đọc khi user bấm chip (hoặc dùng `PasteButton`), sau đó `DeviceCode.extract` → mở sheet đã điền sẵn.

**Done khi:** từ Home Screen nhấn giữ icon → "Nhập device code" mở thẳng sheet (cả cold & warm launch); `codexcockpit://device?code=...` mở sheet đã điền sẵn; nút nổi luôn thấy trên tab Tổng quan.

### Task 5 — Thiết kế lại `DeviceCodeSheet`

Chuyển ra file riêng `CodexCockpit/Views/DeviceCodeSheet.swift`, dùng chung cho mọi lối vào.

- Ô nhập lớn monospaced, `@FocusState` → **bàn phím bật ngay** khi sheet mở (`.onAppear { focused = true }`), `.textContentType(.oneTimeCode)`, `.keyboardType(.asciiCapable)`, `.textInputAutocapitalization(.characters)`, `.autocorrectionDisabled()`, `.submitLabel(.go)`.
- Format trực tiếp khi gõ bằng `DeviceCode.normalize` (giữ con trỏ ở cuối).
- `PasteButton(payloadType: String.self)` của SwiftUI (iOS 16+, không hiện popup xin quyền) → `DeviceCode.extract`.
- **Hàng chip chọn profile** (ngang, scroll): mỗi chip = `ProfileArtwork` nhỏ + tên account mapping. Mặc định: `request.accountID` → profile đó; nếu không có → `lastDeviceProfile`. Đổi chip → `WebViewPool.prewarm`.
- **Tự đi tiếp**: khi `DeviceCode.parse` thành công (đủ độ dài) → haptic `.success`, đợi 250 ms (cho user thấy), rồi tự gọi `open`. Có nút "Mở OpenAI" cho trường hợp code không chuẩn.
- `open`: copy code vào clipboard (giữ hành vi cũ), lưu `lastDeviceProfile`, đóng sheet, `router` điều hướng tới `.browser(accountID, BrowserLaunch(mode: .device, code:...))` trên tab hiện tại (chuyển về tab Tổng quan nếu đang ở Cài đặt). Nếu đang đứng sẵn trong `AccountBrowserView` của đúng account → không push thêm, chỉ `browser.openDeviceLogin`.
- `.presentationDetents([.height(360), .medium])`, `.presentationDragIndicator(.visible)`.
- Accessibility identifiers: `device-code-field`, `device-code-open`, `device-code-profile-<id>`.

**Done khi:** UI test (Task 9) nhập "abcdefghi" → field hiển thị "ABCD-EFGHI" và tự chuyển màn.

### Task 6 — "Ủy quyền lại" song song + màn hình theo dõi

1. Trong `AccountDetailView` nút "Ủy quyền lại": **điều hướng ngay** tới `.browser(accountID, BrowserLaunch(mode: .device, code: nil, ...))`, đồng thời `Task { await store.beginReauthorization(accountID:) }`.
2. `AccountBrowserView` quan sát `store.loginSessions[accountID]`; khi `userCode` xuất hiện → `browser.openDeviceLogin(code:)` (trang đã warm thì chỉ điền).
3. Thanh trạng thái dính ở đầu web view (`DeviceAuthBanner`): code lớn + nút copy + trạng thái (`Đang lấy code…` / `Đã điền, hãy bấm Continue & Authorize` / `Hoàn tất ✓` / lỗi). Ẩn khi không ở mode device.
4. `CockpitStore.startPolling`: poll **0.5 s** khi `status == "creating"` (chưa có code), **2 s** khi `waiting`; dừng khi app background quá 15 phút hoặc session hết hạn (`expiresAt`). Xử lý `beginReauthorization` trả về `creating` không có code (sau Task 11 server trả sớm).
5. Khi `succeeded`: haptic `.success`, banner "Hoàn tất", sau 1.2 s tự `pop` về `AccountDetailView` (router `cockpitPath.removeLast()` nếu top là browser của account đó), quota đã được `replace`.

**Done khi:** bấm "Ủy quyền lại" thấy trang OpenAI ngay lập tức, code tự điền khi VPS trả về, tự quay lại khi xong.

### Task 7 — Tùy chọn trong Cài đặt

Trong `SettingsView` thêm section "Device code":
- Toggle "Tự gửi code sau khi điền" (`@AppStorage("CodexCockpit.autoSubmitCode.v1")`, mặc định **false**). Mô tả: chỉ gửi bước nhập code, bước cấp quyền bạn vẫn tự bấm.
- Toggle "Giữ ấm trang đăng nhập" (`CodexCockpit.prewarm.v1`, mặc định true) — tắt thì `WebViewPool` không prewarm.

---

## Giai đoạn P1 — WebKit nhớ tài khoản ChatGPT

### Task 8a — Trạng thái đăng nhập từng profile

- `ProfileSessionInspector.isSignedIn(profile:) async -> SessionState` đọc `dataStore.httpCookieStore.allCookies()`; coi là đăng nhập nếu có cookie session chưa hết hạn của `chatgpt.com` hoặc `auth.openai.com` (tên cookie đặt thành hằng số mảng, ví dụ chứa `session-token`; đừng hardcode một tên duy nhất).
- `AccountsView` + `webKitCard` trong `AccountDetailView`: badge "Đã đăng nhập" (xanh) / "Cần đăng nhập" (cam). Refresh khi màn xuất hiện.

### Task 8b — `CredentialVault` (Keychain, Face ID)

File mới: `CodexCockpit/Services/CredentialVault.swift`

- Protocol `CredentialStoring` + impl Keychain (để unit test bằng impl in-memory).
- Item `kSecClassGenericPassword`, `kSecAttrService = "vn.nam.CodexCockpit.chatgpt"`, `kSecAttrAccount = profile.id`. Value = JSON `{ "email": ..., "secret": ... }`.
- `kSecAttrAccessControl` = `SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil)` → không vào iCloud/backup, đọc cần Face ID/mật mã. Dùng một `LAContext` với `touchIDAuthenticationAllowableReuseDuration = 300` để không hỏi Face ID liên tục trong 5 phút.
- Email lưu thêm bản **không khoá** (item riêng, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) để điền email không cần Face ID; chỉ mật khẩu cần Face ID.
- UI: trong `AccountDetailView` → card WebKit → "Tài khoản ChatGPT đã lưu" (email hiển thị, nút Sửa/Xoá). Form nhập dùng `SecureField`, `.textContentType(.username / .password)` để iOS cho phép AutoFill từ iCloud Keychain/1Password **vào form của app** (form native thì AutoFill hoạt động).
- Xoá session profile (Task 3) **không** xoá vault; có nút xoá riêng.

### Task 8c — Tự điền đăng nhập OpenAI

- User script thứ hai (cùng cơ chế Task 2) chỉ chạy khi `location.host` ∈ {`auth.openai.com`} và trang có `input[type=email]`/`input[name=email]`/`input[autocomplete=username]` hoặc `input[type=password]`.
- Script **không chứa** dữ liệu; nó post message `{type:"loginFieldVisible", field:"email"|"password"}` về native. Native kiểm tra `webView.url.host == "auth.openai.com"` (bắt buộc, chống trang khác giả mạo), đọc vault, rồi `evaluateJavaScript("__cockpitFillLogin(<json>)", in: nil, in: .defaultClient)` điền đúng field đó (setter gốc + input/change event).
- **Không** tự bấm Continue/Login. Hiện thanh nhỏ phía dưới web view: "Đã điền email ✓ — bấm Continue" / "Đã điền mật khẩu ✓".
- Bước mật khẩu cần Face ID: nếu user huỷ Face ID → không điền, hiện nút "Điền mật khẩu" để thử lại.
- Nếu trang là chọn Google/Apple/Microsoft SSO → không làm gì (ghi chú trong UI vault: "Đăng nhập Google có thể bị Google chặn trong WebView nhúng; khi đó chỉ cookie được giữ").
- Ghi rõ trong README: mật khẩu chỉ ở Keychain thiết bị, không đồng bộ, không gửi VPS.
- `verify_project.py`: thêm assert `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` có trong `CredentialVault.swift` và không có `kSecAttrSynchronizable` = true.

**Done khi:** profile đã lưu vault, mở `auth.openai.com` login → email tự điền; bước mật khẩu → Face ID → tự điền; không có request mạng nào ngoài OpenAI mang dữ liệu đó.

---

## Giai đoạn P2 — Mượt & nhanh tổng thể

### Task 9 — Cache snapshot, khởi động tức thì

- `CockpitAPI.status()` trả thêm raw `Data`; `SnapshotCache` ghi atomically vào `Application Support/status-cache.json` (`.completeFileProtectionUntilFirstUserAuthentication`).
- `CockpitStore.init` load cache đồng bộ (nhỏ) → `accounts` có ngay; `load()` refresh nền. Header hiện "Cập nhật lúc HH:mm" + chấm vàng nếu cache > 5 phút.
- Refresh tự động khi `scenePhase` → `.active` nếu dữ liệu > 60 s.

### Task 10 — Giảm giật

- Lỗi: thay `.alert` ở `CockpitView` bằng banner inline tự ẩn sau 4 s (`ErrorToast`), lỗi không chặn tương tác.
- `BrowserState.update`: chỉ gán khi giá trị thay đổi; `progress` throttle ≤ 10 lần/s và làm tròn 0.05.
- `MiniQuotaRow`/`QuotaProgressRow`: bỏ `GeometryReader`, dùng `Capsule().fill(color).scaleEffect(x: ratio, anchor: .leading)` trên nền capsule.
- `glassCard` trong list: giảm `shadow` (radius nhỏ, hoặc bỏ trong `AccountOverviewCard`), cân nhắc `.compositingGroup()`.
- Skeleton (`.redacted(reason: .placeholder)`) thay `ProgressView("Đang tải quota…")` khi chưa có cache.
- Haptics: refresh xong (`.light`), reset credit thành công (`.success`), lỗi (`.error`).
- `URLSession`: tạo session riêng với `timeoutIntervalForRequest = 15` cho `app-status`/`app-refresh` (giữ 35 s cho `app-auth/start`).

### Task 11 — Server VPS (tuỳ chọn, làm cuối, cần user đồng ý trước khi sửa VPS)

Server **không nằm trong git**. Trước khi sửa: `cp server.py server.py.bak-$(date +%Y%m%d-%H%M%S)`.

- `start_login`: giảm `session["ready"].wait(timeout=15)` xuống `timeout=2` → trả về sớm với `status: "creating"`; app (Task 6) đã poll 0.5 s cho trạng thái này.
- Kiểm tra: `python3 -m py_compile server.py`, `python3 smoke_device_login.py`, `systemctl restart codex-cockpit && systemctl is-active codex-cockpit`, `curl` `app-status` qua localhost:8787 trả 200/401 hợp lệ.
- Rollback nếu lỗi: copy lại file backup, restart.

---

## Task 12 — Kiểm thử & đo

- **Unit**: `DeviceCodeTests`, `DeepLinkTests`, `CredentialVaultTests` (in-memory store), `WebViewPoolTests` (LRU/evict logic tách thành struct thuần), `SnapshotCacheTests`.
- **UI test** (`UITEST_MODE`):
  - `"static"` hiện có giữ nguyên.
  - Thêm `"device-sheet"`: `RootView` không gọi VPS, nạp 2 account giả; test: tap `device-code-fab` → sheet → field có focus → gõ `abcdefghi` → giá trị `ABCD-EFGHI` → màn browser xuất hiện (WebView trỏ `about:blank` trong test mode, không ra internet).
  - Test launch bằng URL: `app.open(URL(string:"codexcockpit://device?code=ABCD-EFGHI")!)` (iOS 16.4+ XCUIApplication API) → sheet hiện với code điền sẵn.
- **Đo**: `os_signpost` (`OSSignposter`, subsystem `vn.nam.CodexCockpit`, category `DeviceCode`) interval từ "sheet open" → "codeFilled". Log ra console ở DEBUG.
- `scripts/verify_project.py` thêm kiểm tra: tồn tại `DeviceCodeAutofill.swift`, `WebViewPool.swift`, `codexcockpit` trong `project.yml`.
- Bump `MARKETING_VERSION` → `1.4.0`, `CURRENT_PROJECT_VERSION` +1 trong `project.yml`.

## Thứ tự commit đề xuất

1. Task 1 → 2 → 3 (nền tảng, mỗi task 1 commit)
2. Task 4 → 5 → 6 → 7 (UX device code)
3. Task 8a → 8b → 8c (vault)
4. Task 9 → 10 (mượt)
5. Task 12 (test/đo, có thể làm dần song song)
6. Task 11 chỉ khi user cho phép sửa VPS.

Sau mỗi giai đoạn: chạy `python scripts/verify_project.py`, cập nhật README, báo user để push lên CI build IPA.

---

## Phụ lục — Đồng bộ với `origin/main` (11 commit mới, tới `1401b64`)

Plan này được viết dựa trên `e7e1db8`. Trước khi làm Task 1: `git pull` lên `origin/main` (`1401b64`) rồi tạo branch `ux/fast-device-code` từ đó. Điều chỉnh theo code mới:

- `verify_project.py` mới có thêm nhiều assert. Không được phá chúng. Script WebKit **không được** chứa `document.cookie`, `localStorage`, `sessionStorage`. Task 2 và 8c phải tuân theo; Task 8a đọc cookie qua `WKHTTPCookieStore` native, không qua JS.
- Đã có `.refreshable` + `store.refreshAll()` và refresh theo `scenePhase == .active` trong `RootView`. Task 9 và 10 tái sử dụng chúng, không làm lại.
- Đã có `WebIdentityBridge` / identity scanner (`callAsyncJavaScript`, `/api/auth/session`). Task 8a nên lấy trạng thái đăng nhập từ scanner này thay vì viết inspector mới.
- Đã có Keychain store cho app token (`credentials.load()`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). `CredentialVault` (Task 8b) theo cùng pattern nhưng dùng service riêng và `WhenUnlockedThisDeviceOnly` + `.userPresence` cho mật khẩu.
- `ProfileWebView.swift` đã đổi (await identity JS). Task 3 (pool) phải giữ hook `onIdentityDetected`.
