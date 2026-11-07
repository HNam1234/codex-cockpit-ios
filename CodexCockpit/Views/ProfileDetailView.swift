import SwiftUI
import UIKit

struct ProfileDetailView: View {
    let profile: AccountProfile
    @StateObject private var browser = BrowserState()
    @State private var showingDeviceCode = false
    @State private var showingClearConfirmation = false
    @State private var webViewGeneration = UUID()

    var body: some View {
        VStack(spacing: 0) {
            quickActions
            Divider()
            ZStack(alignment: .top) {
                ProfileWebView(
                    dataStoreIdentifier: profile.dataStoreIdentifier,
                    initialURL: AppURLs.chatGPT,
                    state: browser
                )
                .id(webViewGeneration)

                if browser.isLoading {
                    ProgressView(value: browser.progress).progressViewStyle(.linear)
                }
            }
            Divider()
            browserBar
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDeviceCode) {
            DeviceCodeSheet { code in
                if !code.isEmpty { UIPasteboard.general.string = code }
                browser.openDeviceLogin(code: code)
                showingDeviceCode = false
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Xóa toàn bộ cookie và session của \(profile.name)?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
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

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                action("ChatGPT", "bubble.left.and.bubble.right.fill") { browser.open(AppURLs.chatGPT) }
                action("Nhập device code", "key.horizontal.fill") { showingDeviceCode = true }
                action("Đăng nhập", "person.crop.circle.badge.checkmark") {
                    browser.open(URL(string: "https://chatgpt.com/auth/login")!)
                }
                action("Xóa session", "trash", destructive: true) { showingClearConfirmation = true }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func action(
        _ title: String,
        _ icon: String,
        destructive: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(destructive ? .red : profile.tint)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background((destructive ? Color.red : profile.tint).opacity(0.1), in: Capsule())
        }
    }

    private var browserBar: some View {
        HStack {
            Button { browser.goBack() } label: { Image(systemName: "chevron.backward") }
                .disabled(!browser.canGoBack)
            Spacer()
            Button { browser.goForward() } label: { Image(systemName: "chevron.forward") }
                .disabled(!browser.canGoForward)
            Spacer()
            Text(browser.currentURL?.host ?? "Đang mở…")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
            Spacer()
            Button { showingDeviceCode = true } label: { Image(systemName: "key.horizontal") }
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(.bar)
    }
}

private struct DeviceCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    let onOpen: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Mã từ thiết bị mới") {
                    TextField("ABCD-EFGH", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                    Text("Mã chỉ được copy vào clipboard trên iPhone. Trang xác nhận là auth.openai.com trong đúng profile này.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ủy quyền thiết bị")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mở OpenAI") {
                        let clean = code.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
                        onOpen(clean)
                    }
                }
            }
        }
    }
}
