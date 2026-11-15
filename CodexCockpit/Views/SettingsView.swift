import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var tiboNotifications: TiboNotificationManager
    @EnvironmentObject private var mailStore: DisposableMailStore
    @State private var confirmingClearMail = false

    var body: some View {
        ZStack {
            CockpitBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        ProfileArtwork(seed: "settings", symbol: "command", size: 92)
                        Text("Codex Cockpit").font(.title.weight(.bold))
                        Text(L10n.format("settings.version_subtitle", appVersion))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)

                    settingsCard("Thư viện", icon: "square.stack.3d.up.fill", tint: CockpitTheme.violet) {
                        LabeledContent("Tài khoản Codex", value: "\(store.accounts.count)")
                        Divider()
                        LabeledContent("WebKit profiles", value: "\(mappings.profiles.count)")
                        Divider()
                        LabeledContent("Kho dữ liệu", value: "Persistent")
                    }
                    settingsCard("Riêng tư", icon: "lock.shield.fill", tint: .green) {
                        Text("Cookie nằm trong sandbox WebKit trên iPhone. Mỗi session được quản lý hoàn toàn cục bộ.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    settingsCard(L10n.text("mail.settings.title"), icon: "envelope.fill", tint: CockpitTheme.cyan) {
                        LabeledContent(L10n.text("mail.provider.attribution"), value: "\(mailStore.activeMailboxes.count)")
                        Divider()
                        Text(L10n.text("mail.settings.privacy"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !mailStore.mailboxes.isEmpty {
                            Divider()
                            Button(L10n.text("mail.settings.clear"), role: .destructive) {
                                confirmingClearMail = true
                            }
                        }
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
                        Text("Dịch vụ TIBO đọc tracker OpenTheRank và trạng thái công khai @thsottiaux trên X mỗi 15 phút. Tỷ lệ hôm nay là ước tính từ lịch sử + tín hiệu X.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog(
            L10n.text("mail.settings.clear_confirmation"),
            isPresented: $confirmingClearMail,
            titleVisibility: .visible
        ) {
            Button(L10n.text("mail.settings.clear"), role: .destructive) {
                mailStore.clearLocalData()
            }
            Button(L10n.text("mail.cancel"), role: .cancel) {}
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.6.1"
    }

    private func settingsCard<Content: View>(
        _ title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(L10n.text(title), systemImage: icon).font(.headline).foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).glassCard()
    }
}

