import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var tiboNotifications: TiboNotificationManager
    @EnvironmentObject private var credentials: CockpitCredentialModel

    var body: some View {
        ZStack {
            CockpitBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        ProfileArtwork(seed: "settings", symbol: "command", size: 92)
                        Text("Codex Cockpit").font(.title.weight(.bold))
                        Text("\(appVersion) · Premium quota control").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)

                    settingsCard("Kết nối VPS", icon: "key.fill", tint: .blue) {
                        Label(
                            credentials.isConfigured ? "Đã lưu token an toàn" : "Chưa cấu hình token",
                            systemImage: credentials.isConfigured ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(credentials.isConfigured ? .green : .orange)

                        SecureField("COCKPIT_APP_TOKEN", text: $credentials.tokenInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .privacySensitive()
                            .textContentType(.password)

                        HStack {
                            Button("Lưu vào Keychain") {
                                if credentials.save() { store.disconnect() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(credentials.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if credentials.isConfigured {
                                Button("Ngắt kết nối", role: .destructive) {
                                    if credentials.clear() { store.disconnect() }
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let error = credentials.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        Text("Token chỉ nằm trong iOS Keychain trên thiết bị này; source code và IPA public không chứa token.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    settingsCard("Thư viện", icon: "square.stack.3d.up.fill", tint: CockpitTheme.violet) {
                        LabeledContent("Tài khoản Codex", value: "\(store.accounts.count)")
                        Divider()
                        LabeledContent("WebKit profiles", value: "\(mappings.profiles.count)")
                        Divider()
                        LabeledContent("Kho dữ liệu", value: "Persistent")
                    }
                    settingsCard("Riêng tư", icon: "lock.shield.fill", tint: .green) {
                        Text("Cookie nằm trong sandbox WebKit trên iPhone. App không đọc hoặc gửi cookie lên VPS.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    settingsCard("TIBO", icon: "waveform.path.ecg", tint: CockpitTheme.accent) {
                        Toggle(isOn: Binding(
                            get: { tiboNotifications.isEnabled },
                            set: { tiboNotifications.setEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Thông báo tín hiệu mạnh")
                                Text("Chỉ báo khi trạng thái mới là có khả năng hoặc đã xác nhận.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(tiboNotifications.isRequestingPermission)
                        if tiboNotifications.isRequestingPermission {
                            ProgressView("Đang xin quyền thông báo…")
                                .font(.caption)
                        }
                        if tiboNotifications.permissionDenied {
                            Label("Quyền thông báo đang bị tắt trong Cài đặt iOS.", systemImage: "bell.slash.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Divider()
                        Text("VPS đọc tracker OpenTheRank và trạng thái công khai @thsottiaux trên X mỗi 15 phút. Tỷ lệ hôm nay là ước tính từ lịch sử + tín hiệu X; không dữ liệu tài khoản nào được gửi ra ngoài.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4.0"
    }

    private func settingsCard<Content: View>(
        _ title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).glassCard()
    }
}

