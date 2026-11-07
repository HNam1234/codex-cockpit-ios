import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore

    var body: some View {
        Form {
            Section("Bảo mật") {
                Label("Dashboard native dùng token có thể thu hồi", systemImage: "lock.shield.fill")
                Text("Cookie của từng profile nằm trong sandbox WebKit trên iPhone; app không đọc hoặc gửi cookie lên VPS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Profile") {
                LabeledContent("Tài khoản Codex", value: "\(store.accounts.count)")
                LabeledContent("WebKit profiles", value: "\(mappings.profiles.count)")
                LabeledContent("Kho dữ liệu", value: "Persistent, tách biệt")
                LabeledContent("iOS tối thiểu", value: "17.0")
            }
            Section("TIBO") {
                Text("VPS chỉ đọc feed reset công khai từ OpenTheRank mỗi 15 phút. Không quota, email, token hoặc dữ liệu tài khoản nào được gửi cho TIBO.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Phiên bản") {
                LabeledContent("Codex Cockpit", value: "1.2.0 (7)")
            }
        }
        .navigationTitle("Cài đặt")
    }
}

