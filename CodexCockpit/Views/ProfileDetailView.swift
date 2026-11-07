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
        Group {
            if let account = store.account(id: accountID) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.identity).font(.title3.weight(.bold))
                            Text([account.name, account.plan?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let error = account.error, !account.ok {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                    }

                    Section("Quota") {
                        ForEach(account.windows) { window in
                            QuotaProgressRow(window: window).padding(.vertical, 6)
                        }
                    }

                    Section("WebKit mapping") {
                        LabeledContent("Profile hiện tại", value: mappings.profile(for: accountID).name)
                        Button("Đổi profile (tự swap, không xóa cookie)") { showingMapping = true }
                        Button {
                            router.openBrowser(accountID: accountID)
                        } label: { Label("Mở Web", systemImage: "safari.fill") }
                    }

                    Section("Tác vụ tài khoản") {
                        Button {
                            Task { await store.refresh(accountID: accountID) }
                        } label: { Label("Cập nhật usage ngay", systemImage: "arrow.clockwise") }
                        .disabled(store.busyAccounts.contains(accountID))

                        Button {
                            Task {
                                await store.beginReauthorization(accountID: accountID)
                                if let session = store.loginSessions[accountID], let code = session.userCode {
                                    router.openBrowser(
                                        accountID: accountID,
                                        launch: BrowserLaunch(mode: .device, code: code, verificationURL: session.verificationURL)
                                    )
                                }
                            }
                        } label: { Label("Ủy quyền lại", systemImage: "key.horizontal.fill") }
                        .disabled(store.busyAccounts.contains(accountID) || store.capabilities?.reauthorize == false)

                        if account.resetCredits > 0, store.capabilities?.resetCredit == true {
                            Button(role: .destructive) { confirmingReset = true } label: {
                                Label("Dùng reset credit (còn \(account.resetCredits))", systemImage: "arrow.counterclockwise.circle.fill")
                            }
                        }
                    }

                    if let session = store.loginSessions[accountID] {
                        AuthorizationStatusCard(session: session) {
                            router.openBrowser(
                                accountID: accountID,
                                launch: BrowserLaunch(mode: .device, code: session.userCode, verificationURL: session.verificationURL)
                            )
                        }
                    }
                }
            } else {
                ContentUnavailableView("Không tìm thấy tài khoản", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle("Chi tiết")
        .navigationBarTitleDisplayMode(.inline)
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
        Section("Ủy quyền") {
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
                            Text(owner?.identity ?? "Trống").font(.caption).foregroundStyle(.secondary)
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
    @EnvironmentObject private var mappings: ProfileMappingStore
    @StateObject private var browser = BrowserState()
    @State private var showingCodeEntry = false
    @State private var showingClear = false
    @State private var webViewGeneration = UUID()

    var body: some View {
        let profile = mappings.profile(for: accountID)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ProfileWebView(
                    dataStoreIdentifier: profile.dataStoreIdentifier,
                    initialRequest: URLRequest(url: initialURL),
                    state: browser
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
