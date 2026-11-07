import SwiftUI

struct SettingsView: View {
    @State private var statusText: String?
    @EnvironmentObject private var directory: AccountDirectory

    var body: some View {
        Form {
            Section("Bảo mật") {
                Label("Khóa ứng dụng đã tắt", systemImage: "lock.open.fill")
                Text("Cookie của từng profile nằm trong sandbox WebKit trên iPhone; app không đọc hoặc gửi cookie lên VPS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Profile") {
                LabeledContent("Số profile ChatGPT", value: "\(directory.profiles.count)")
                LabeledContent("Kho dữ liệu", value: "Persistent, tách biệt")
                LabeledContent("iOS tối thiểu", value: "17.0")
            }
            Section("Dashboard") {
                Text(AppURLs.dashboard.absoluteString)
                    .font(.caption.monospaced()).textSelection(.enabled)
                Text("App tự khôi phục phiên dashboard bằng khóa riêng có thể thu hồi; không cần link Telegram. Telegram tiếp tục gửi cảnh báo realtime.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Phiên bản") {
                LabeledContent("Codex Cockpit", value: "1.1.0 (6)")
                if let statusText { Text(statusText).font(.footnote) }
            }
        }
        .navigationTitle("Cài đặt")
    }
}

