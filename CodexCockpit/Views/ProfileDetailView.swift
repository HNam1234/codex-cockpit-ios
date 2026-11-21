import SwiftUI
import UIKit

struct AccountDetailView: View {
    let accountID: String
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var router: AppRouter
    @State private var showingMapping = false
    @State private var confirmingReset = false
    @State private var resetMessage: String?

    var body: some View {
        ZStack {
            CockpitBackdrop()
            if let account = store.account(id: accountID) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        accountHero(account)
                        quotaCard(account)
                        webKitCard
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
        .sheet(isPresented: $showingMapping) { MappingPicker(accountID: accountID) }
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
    }

    private func accountHero(_ account: AccountSnapshot) -> some View {
        VStack(spacing: 13) {
            ProfileArtwork(seed: account.id, symbol: "command", size: 118)
            VStack(spacing: 4) {
                Text(mappings.displayIdentity(for: account)).font(.title2.weight(.bold)).lineLimit(1)
                Text([account.name, account.plan?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            if let error = account.error, !account.ok {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 10)
    }

    private func quotaCard(_ account: AccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "Quota", caption: "Còn lại")
            ForEach(account.windows) { window in QuotaProgressRow(window: window) }
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
                    Text("Cookie được giữ khi đổi mapping").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Đổi") { showingMapping = true }.font(.subheadline.weight(.bold))
            }
            Button { router.openBrowser(accountID: accountID) } label: {
                Label("Mở Web", systemImage: "safari.fill")
            }
            .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.accent))
        }
        .padding(18).glassCard()
    }

    private func actionGrid(_ account: AccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(title: "Điều khiển")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionTile("Cập nhật", icon: "arrow.clockwise", tint: .blue) {
                    Task { await store.refresh(accountID: accountID) }
                }
                actionTile("Ủy quyền lại", icon: "key.horizontal.fill", tint: CockpitTheme.violet) {
                    Task {
                        await store.beginReauthorization(accountID: accountID)
                        if let session = store.loginSessions[accountID], let code = session.userCode {
                            router.openBrowser(
                                accountID: accountID,
                                launch: BrowserLaunch(mode: .device, code: code, verificationURL: session.verificationURL)
                            )
                        }
                    }
                }
                if account.resetCredits > 0, store.capabilities?.resetCredit == true {
                    actionTile("Reset credit · \(account.resetCredits)", icon: "arrow.counterclockwise.circle.fill", tint: CockpitTheme.accent) {
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
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(15).glassCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .disabled(store.busyAccounts.contains(accountID))
    }

    private func resetText(_ outcome: String) -> String {
        switch outcome {
        case "reset": return "Đã reset usage thành công."
        case "nothingToReset": return "Hiện không có usage cần reset."
        case "noCredit": return "Tài khoản không còn reset credit."
        case "alreadyRedeemed": return "Yêu cầu này đã được xử lý trước đó."
        default: return "VPS trả kết quả: \(outcome)"
        }
    }
}

private struct AuthorizationStatusCard: View {
    let session: LoginSession
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Ủy quyền", caption: session.status == "succeeded" ? "Hoàn tất" : session.status)
            LabeledContent("Trạng thái", value: session.status == "succeeded" ? "Hoàn tất" : session.status)
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

private struct MappingPicker: View {
    let accountID: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var store: CockpitStore

    var body: some View {
        NavigationStack {
            List(mappings.profiles) { profile in
                let ownerID = mappings.mappedAccountID(for: profile.id)
                let owner = ownerID.flatMap { store.account(id: $0) }
                Button {
                    mappings.assign(accountID: accountID, to: profile.id)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name).foregroundStyle(.primary)
                            Text(owner.map { mappings.displayIdentity(for: $0) } ?? "Trống")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if mappings.profile(for: accountID).id == profile.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Chọn WebKit")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { mappings.addProfile() } label: { Image(systemName: "plus") } }
            }
        }
    }
}

struct AccountBrowserView: View {
    let accountID: String
    let launch: BrowserLaunch
    let profileBinding: BrowserProfileBinding
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @StateObject private var browser = BrowserState()
    @State private var showingCodeEntry = false
    @State private var showingClear = false
    @State private var webViewGeneration = UUID()

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
                browser.pendingDeviceCode = code
                UIPasteboard.general.string = code
            }
        }
        .sheet(isPresented: $showingCodeEntry) {
            DeviceCodeSheet { code in
                if !code.isEmpty { UIPasteboard.general.string = code }
                browser.openDeviceLogin(code: code)
                showingCodeEntry = false
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Xóa cookie và session của \(profile.name)?", isPresented: $showingClear) {
            Button("Xóa profile", role: .destructive) {
                Task {
                    browser.webView?.stopLoading()
                    browser.webView = nil
                    try? await ProfileDataStore.clear(identifier: profile.dataStoreIdentifier)
                    mappings.clearIdentity(for: profile.id)
                    webViewGeneration = UUID()
                }
            }
        }
    }

    private var initialURL: URL {
        if let value = launch.verificationURL, let url = URL(string: value) { return url }
        return launch.mode == .device ? AppURLs.deviceLogin : AppURLs.chatGPT
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
                        .onChange(of: code) { _, newValue in
                            let normalized = DeviceCode.normalize(newValue)
                            if normalized != newValue { code = normalized }
                        }
                    Text("Mã chỉ được copy cục bộ và điền vào auth.openai.com trong WebKit đang mở.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ủy quyền thiết bị")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mở OpenAI") {
                        onOpen(DeviceCode.normalize(code))
                    }
                }
            }
        }
    }
}
