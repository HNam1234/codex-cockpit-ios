import SwiftUI
import UIKit

struct AccountDetailView: View {
    let accountID: String
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var mailStore: DisposableMailStore
    @State private var confirmingReset = false
    @State private var resetMessage: String?
    @State private var showingDeviceAuthorization = false

    var body: some View {
        ZStack {
            CockpitBackdrop()
            if let account = store.account(id: accountID) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        accountHero(account)
                        quotaCard(account)
                        webKitCard
                        temporaryMailCard(account)
                        actionGrid(account)
                    if let session = store.loginSessions[accountID] {
                        AuthorizationStatusCard(session: session) {
                            router.openBrowser(
                                accountID: accountID,
                                launch: BrowserLaunch(mode: .device, code: session.userCode, verificationURL: session.verificationURL)
                            )
                        }
                    }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 28)
                }
            } else {
                ContentUnavailableView("Không tìm thấy tài khoản", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle("Chi tiết")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog("Dùng một reset credit cho tài khoản này?", isPresented: $confirmingReset) {
            Button("Xác nhận reset", role: .destructive) {
                Task {
                    if let outcome = await store.consumeResetCredit(accountID: accountID) {
                        resetMessage = resetText(outcome)
                    }
                }
            }
        }
        .alert("Reset usage", isPresented: Binding(get: { resetMessage != nil }, set: { if !$0 { resetMessage = nil } })) {
            Button("OK") { resetMessage = nil }
        } message: { Text(resetMessage ?? "") }
        .sheet(isPresented: $showingDeviceAuthorization) {
            if let account = store.account(id: accountID) {
                PCDeviceCodeSheet(
                    accountID: accountID,
                    accountName: mappings.displayIdentity(for: account)
                ) { code in
                    router.openBrowser(
                        accountID: accountID,
                        launch: BrowserLaunch(
                            mode: .device,
                            code: code,
                            verificationURL: AppURLs.deviceLogin.absoluteString
                        )
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func accountHero(_ account: AccountSnapshot) -> some View {
        VStack(spacing: 13) {
            ProfileArtwork(seed: account.id, symbol: "command", size: 118)
            VStack(spacing: 4) {
                Text(mappings.displayIdentity(for: account)).font(.title2.weight(.bold)).lineLimit(1)
                Text((account.isLocalDirect
                      ? [account.plan?.uppercased()]
                      : [account.name, account.plan?.uppercased()])
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                AccountHealthBadge(health: account.health())
                if let remaining = account.subscriptionRemainingText() {
                    HStack(spacing: 6) {
                        Label(remaining, systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(account.subscriptionIsExpired() ? .red : CockpitTheme.violet)
                        if let expiration = account.subscriptionExpirationDate {
                            Text(L10n.format(
                                "subscription.expires_on",
                                expiration.formatted(date: .numeric, time: .omitted)
                            ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let error = account.error,
               !account.isAuthenticated() {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 10)
    }

    private func quotaCard(_ account: AccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "Quota", caption: "Còn lại")
            if account.windows.isEmpty {
                Label(
                    L10n.text("quota.unavailable.sign_in"),
                    systemImage: "gauge.with.dots.needle.33percent"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Button { startQuotaLogin() } label: {
                    Label(L10n.text("quota.login.action"), systemImage: "person.badge.key.fill")
                }
                .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.accent))
                .disabled(store.busyAccounts.contains(accountID))
            } else {
                ForEach(account.windows) { window in QuotaProgressRow(window: window) }
            }
        }
        .padding(18).glassCard()
    }

    private var webKitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "WebKit", caption: "Session riêng")
            HStack(spacing: 12) {
                ProfileArtwork(seed: mappings.profile(for: accountID).id, symbol: "safari.fill", size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mappings.profile(for: accountID).name).font(.headline)
                    Text("WebKit riêng cố định cho account này").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
            Button { router.openBrowser(accountID: accountID) } label: {
                Label("Mở Web", systemImage: "safari.fill")
            }
            .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.accent))
        }
        .padding(18).glassCard()
    }

    private func temporaryMailCard(_ account: AccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: L10n.text("mail.account.card"), caption: L10n.text("mail.provider.attribution"))
            if let mailbox = mailStore.mailbox(linkedTo: accountID) {
                HStack(spacing: 12) {
                    ProfileArtwork(seed: mailbox.address, symbol: "envelope.fill", size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mailbox.address).font(.headline).lineLimit(1)
                        Text(L10n.format("mail.remaining_days", mailbox.remainingDays()))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CockpitTheme.violet)
                        if mailbox.unreadCount > 0 {
                            Text(L10n.format("mail.unread_count", mailbox.unreadCount))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(CockpitTheme.accent)
                        }
                    }
                    Spacer()
                }
                Button { router.openMailbox(mailbox.id) } label: {
                    Label(L10n.text("mail.open"), systemImage: "tray.full.fill")
                }
                .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.cyan))
            } else {
                Text(L10n.text("mail.empty.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        _ = await mailStore.create(lifetime: .default, linkedAccountID: accountID)
                    }
                } label: {
                    if mailStore.isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Label(L10n.text("mail.create_for_account"), systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.cyan))
                .disabled(mailStore.isCreating)
            }
        }
        .padding(18)
        .glassCard()
    }

    private func actionGrid(_ account: AccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(title: "Điều khiển")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionTile("Cập nhật", icon: "arrow.clockwise", tint: .blue) {
                    Task { await store.refresh(accountID: accountID) }
                }
                actionTile(L10n.text("quota.login.action"), icon: "person.badge.key.fill", tint: CockpitTheme.accent) {
                    startQuotaLogin()
                }
                actionTile("Nhập code PC", icon: "key.horizontal.fill", tint: CockpitTheme.violet) {
                    showingDeviceAuthorization = true
                }
                if account.resetCredits > 0, store.capabilities?.resetCredit == true {
                    actionTile(
                        L10n.format("reset.credit_count", account.resetCredits),
                        icon: "arrow.counterclockwise.circle.fill",
                        tint: CockpitTheme.accent
                    ) {
                        confirmingReset = true
                    }
                }
            }
        }
    }

    private func actionTile(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(tint)
                Text(L10n.text(title)).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(15).glassCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .disabled(store.busyAccounts.contains(accountID))
    }

    private func startQuotaLogin() {
        mappings.createDedicatedProfile(for: accountID)
        Task {
            guard let session = await store.beginReauthorization(accountID: accountID) else { return }
            guard session.status != "failed",
                  let code = session.userCode,
                  !DeviceCodeAssistant.normalized(code).isEmpty else {
                store.errorMessage = session.error ?? L10n.text("quota.login.error.no_code")
                return
            }
            router.openBrowser(
                accountID: accountID,
                launch: BrowserLaunch(
                    mode: .device,
                    code: code,
                    verificationURL: session.verificationURL
                )
            )
        }
    }

    private func resetText(_ outcome: String) -> String {
        switch outcome {
        case "reset": return L10n.text("reset.result.success")
        case "nothingToReset": return L10n.text("reset.result.nothing")
        case "noCredit": return L10n.text("reset.result.no_credit")
        case "alreadyRedeemed": return L10n.text("reset.result.redeemed")
        default: return L10n.format("reset.result.unknown", outcome)
        }
    }
}

private struct AuthorizationStatusCard: View {
    let session: LoginSession
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "Ủy quyền",
                caption: session.status == "succeeded" ? L10n.text("authorization.completed") : session.status
            )
            LabeledContent(
                "Trạng thái",
                value: session.status == "succeeded" ? L10n.text("authorization.completed") : session.status
            )
            if let code = session.userCode {
                HStack {
                    Text(code).font(.title3.monospaced().weight(.bold)).textSelection(.enabled)
                    Spacer()
                    Button { UIPasteboard.general.string = code } label: { Image(systemName: "doc.on.doc") }
                }
                Button("Mở trang xác nhận trong WebKit này", action: open)
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
        }
        .padding(18).glassCard()
    }
}

struct AccountBrowserView: View {
    let accountID: String
    let launch: BrowserLaunch
    let profileBinding: BrowserProfileBinding
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var directOAuth: DirectOAuthStore
    @StateObject private var browser = BrowserState()
    @State private var showingCodeEntry = false
    @State private var showingCockpitOAuth = false
    @State private var showingClear = false
    @State private var cockpitOAuthResult: CockpitOAuthCallback?
    @State private var directOAuthResult: DirectOAuthRegistration?
    @State private var directOAuthHasLiveQuota = false
    @State private var isCompletingDirectOAuth = false
    @State private var webViewGeneration = UUID()
    @State private var didPrepareDirectOAuth = false
    @State private var didPrepareCockpitOAuth = false

    var body: some View {
        let profile = profileBinding.profile(in: mappings)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ProfileWebView(
                    dataStoreIdentifier: profile.dataStoreIdentifier,
                    initialRequest: URLRequest(url: initialURL),
                    state: browser,
                    onIdentityDetected: { identity in
                        mappings.record(identity: identity, for: profile.id, accounts: store.accounts)
                    }
                )
                .id(webViewGeneration)
                if browser.isLoading { ProgressView(value: browser.progress).progressViewStyle(.linear) }
            }
            if let code = browser.deviceCode {
                deviceCodeBar(code)
            }
            if launch.mode == .device,
               let session = store.loginSessions[accountID] {
                if session.status == "succeeded" {
                    Label(L10n.text("quota.login.completed"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(10)
                } else if let error = session.error {
                    Text(error).font(.caption).foregroundStyle(.red).padding(10)
                } else {
                    Label(L10n.text("quota.login.waiting"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.secondary).padding(10)
                }
            }
            if isCompletingDirectOAuth {
                Label(L10n.text("oauth.direct.syncingQuota"), systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CockpitTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
            }
            if let error = browser.errorMessage,
               error.hasPrefix("oauth.relay.error.") || error.hasPrefix("oauth.direct.error.") {
                Label(L10n.text(error), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
            }
            Divider()
            HStack {
                Button { browser.goBack() } label: { Image(systemName: "chevron.backward") }.disabled(!browser.canGoBack)
                Spacer()
                Button { browser.goForward() } label: { Image(systemName: "chevron.forward") }.disabled(!browser.canGoForward)
                Spacer()
                Text(browser.currentURL?.host ?? profile.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                Spacer()
                Button { showingCodeEntry = true } label: { Image(systemName: "key.horizontal") }
            }
            .padding(.horizontal, 20).padding(.vertical, 11).background(.bar)
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("ChatGPT") { browser.open(AppURLs.chatGPT) }
                    Button("Nhập device code") { showingCodeEntry = true }
                    Button("Xóa session", role: .destructive) { showingClear = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            if let code = launch.code {
                browser.prepareDeviceCode(code)
                UIPasteboard.general.string = DeviceCodeAssistant.normalized(code)
            }
            if let attempt = launch.directOAuthAttempt, !didPrepareDirectOAuth {
                didPrepareDirectOAuth = true
                browser.prepareDirectOAuth(attempt)
            }
            if let attempt = launch.cockpitOAuthAttempt, !didPrepareCockpitOAuth {
                didPrepareCockpitOAuth = true
                browser.prepareCockpitOAuth(attempt)
            }
        }
        .onChange(of: browser.capturedDirectOAuth) { _, capture in
            guard let capture else { return }
            Task { await completeDirectOAuth(capture) }
        }
        .onChange(of: browser.capturedCockpitOAuthCallback) { _, callback in
            guard let callback else { return }
            UIPasteboard.general.string = callback.url.absoluteString
            cockpitOAuthResult = callback
        }
        .sheet(isPresented: $showingCodeEntry) {
            DeviceCodeSheet { code in
                let normalized = DeviceCodeAssistant.normalized(code)
                if !normalized.isEmpty { UIPasteboard.general.string = normalized }
                browser.openDeviceLogin(code: normalized)
                showingCodeEntry = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingCockpitOAuth) {
            CockpitOAuthEntrySheet(
                accountName: profile.name,
                identity: mappings.webIdentities[profile.id]?.label
                    ?? store.account(id: accountID).map { mappings.displayIdentity(for: $0) }
            ) { attempt in
                didPrepareCockpitOAuth = true
                browser.prepareCockpitOAuth(attempt)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $cockpitOAuthResult) { callback in
            CockpitOAuthResultSheet(callback: callback) {
                clearOAuthCallback(callback)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $directOAuthResult) { registration in
            DirectOAuthSuccessSheet(
                registration: registration,
                showsLiveQuota: directOAuthHasLiveQuota
            ) {
                directOAuthResult = nil
                browser.clearDirectOAuth()
                browser.open(AppURLs.chatGPT)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            L10n.format("browser.clear_confirmation", profile.name),
            isPresented: $showingClear
        ) {
            Button("Xóa profile", role: .destructive) {
                Task {
                    browser.webView?.stopLoading()
                    browser.webView = nil
                    try? await ProfileDataStore.clear(identifier: profile.dataStoreIdentifier)
                    try? directOAuth.clear(profileID: profile.id)
                    store.disconnectLocalOAuth(accountID: accountID)
                    mappings.clearIdentity(for: profile.id)
                    webViewGeneration = UUID()
                }
            }
        }
    }

    private var initialURL: URL {
        if let attempt = launch.directOAuthAttempt { return attempt.authorizationURL }
        if let attempt = launch.cockpitOAuthAttempt { return attempt.authorizationURL }
        if let value = launch.verificationURL, let url = URL(string: value) { return url }
        return launch.mode == .device ? AppURLs.deviceLogin : AppURLs.chatGPT
    }

    private var profile: WebProfile {
        profileBinding.profile(in: mappings)
    }

    private func clearOAuthCallback(_ callback: CockpitOAuthCallback) {
        let callbackValue = callback.url.absoluteString
        if UIPasteboard.general.string == callbackValue {
            UIPasteboard.general.items = []
        }
        browser.clearCockpitOAuth()
        cockpitOAuthResult = nil
    }

    @MainActor
    private func completeDirectOAuth(_ capture: DirectOAuthCapture) async {
        guard !isCompletingDirectOAuth else { return }
        isCompletingDirectOAuth = true
        defer { isCompletingDirectOAuth = false }
        do {
            let registration = try await directOAuth.complete(capture: capture, profileID: profile.id)
            if let identity = WebAccountIdentity(name: registration.name, email: registration.email) {
                mappings.record(
                    identity: identity,
                    for: profile.id,
                    mappedAccountID: accountID,
                    accounts: store.accounts
                )
            }
            if store.account(id: accountID)?.isLocalDirect == true {
                store.completeLocalOAuth(accountID: accountID, email: registration.email)
                directOAuthHasLiveQuota = false
            } else if await store.importDirectOAuth(accountID: accountID, registration: registration) == nil {
                browser.errorMessage = "oauth.direct.error.quotaSync"
                return
            } else {
                directOAuthHasLiveQuota = true
            }
            browser.errorMessage = nil
            directOAuthResult = registration
        } catch let error as DirectOAuthError {
            browser.errorMessage = error.localizationKey
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func deviceCodeBar(_ code: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal.fill").foregroundStyle(CockpitTheme.violet)
            VStack(alignment: .leading, spacing: 1) {
                Text("DEVICE CODE").font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                Text(code).font(.subheadline.monospaced().weight(.bold)).textSelection(.enabled)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = code
            } label: {
                Image(systemName: "doc.on.doc")
            }
            Button("Tự động lại") {
                browser.retryDeviceCodeFill()
            }
            .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("device_code.accessibility", code))
    }
}

private struct DeviceCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    let onOpen: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Device login code") {
                    TextField("ABCD-EFGH", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                    Text("Mã chỉ được copy cục bộ và điền vào auth.openai.com trong WebKit đang mở.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ủy quyền thiết bị")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mở OpenAI") {
                        onOpen(code.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" })
                    }
                }
            }
        }
    }
}
