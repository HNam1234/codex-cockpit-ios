import SwiftUI

struct CockpitView: View {
    @StateObject private var browser = BrowserState()
    @State private var showingLinkEntry = false

    var body: some View {
        ZStack(alignment: .top) {
            if ProcessInfo.processInfo.environment["UITEST_MODE"] == "1" {
                Text("Cockpit ready")
                    .accessibilityIdentifier("cockpit-ready")
            } else {
                ProfileWebView(
                    dataStoreIdentifier: AccountProfile.dashboardDataStoreIdentifier,
                    initialURL: AppURLs.dashboard,
                    state: browser
                )
            }

            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .progressViewStyle(.linear)
            }
        }
        .navigationTitle("Codex Cockpit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { showingLinkEntry = true } label: { Image(systemName: "link.badge.plus") }
                    .accessibilityLabel("Dán link đăng nhập từ Telegram")
            }
        }
        .sheet(isPresented: $showingLinkEntry) {
            DashboardLinkSheet { url in
                browser.open(url)
                showingLinkEntry = false
            }
            .presentationDetents([.medium])
        }
    }
}

private struct DashboardLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorMessage: String?
    let onOpen: (URL) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Kết nối dashboard") {
                    Text("Gửi /web cho bot Telegram, sao chép link rồi dán vào đây một lần.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("https://…/codex/login?t=…", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Đăng nhập Cockpit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mở") {
                        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                              AppURLs.isDashboardLoginLink(url) else {
                            errorMessage = "Link không đúng host/path của Codex Cockpit."
                            return
                        }
                        onOpen(url)
                    }
                }
            }
        }
    }
}
