import SwiftUI

struct SettingsView: View {
    @State private var statusText: String?

    var body: some View {
        Form {
            Section("Bảo mật") {
                Label("Khóa ứng dụng đã tắt", systemImage: "lock.open.fill")
                Text("Cookie của năm profile nằm trong sandbox WebKit trên iPhone; app không đọc hoặc gửi cookie lên VPS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Profile") {
                LabeledContent("Số profile ChatGPT", value: "5")
                LabeledContent("Kho dữ liệu", value: "Persistent, tách biệt")
                LabeledContent("iOS tối thiểu", value: "17.0")
            }
            Section("Dashboard") {
                Text(AppURLs.dashboard.absoluteString)
                    .font(.caption.monospaced()).textSelection(.enabled)
                Text("Dashboard chỉ đọc quota. Telegram tiếp tục gửi cảnh báo realtime.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Phiên bản") {
                LabeledContent("Codex Cockpit", value: "1.0.2 (3)")
                if let statusText { Text(statusText).font(.footnote) }
            }
        }
        .navigationTitle("Cài đặt")
    }
}

