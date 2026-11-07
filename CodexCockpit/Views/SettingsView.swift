import SwiftUI

struct SettingsView: View {
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var statusText: String?

    var body: some View {
        Form {
            Section("Bảo mật") {
                Toggle("Khóa bằng Face ID hoặc mật mã", isOn: $faceIDEnabled)
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
                LabeledContent("Codex Cockpit", value: "1.0.0 (1)")
                if let statusText { Text(statusText).font(.footnote) }
            }
        }
        .navigationTitle("Cài đặt")
    }
}

struct LockView: View {
    @ObservedObject var appLock: AppLockModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 58)).foregroundStyle(.blue)
            Text("Codex Cockpit").font(.title.bold())
            Text("Mở khóa để truy cập năm profile tài khoản.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Mở bằng Face ID / mật mã") {
                Task { await appLock.authenticate() }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            if let error = appLock.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(28)
    }
}
