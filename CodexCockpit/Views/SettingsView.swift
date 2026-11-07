import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore

    var body: some View {
        ZStack {
            CockpitBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        ProfileArtwork(seed: "settings", symbol: "command", size: 92)
                        Text("Codex Cockpit").font(.title.weight(.bold))
                        Text("1.3.0 · Premium quota control").font(.subheadline).foregroundStyle(.secondary)
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
                        Text("Cookie nằm trong sandbox WebKit trên iPhone. App không đọc hoặc gửi cookie lên VPS.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    settingsCard("TIBO", icon: "waveform.path.ecg", tint: CockpitTheme.accent) {
                        Text("VPS đọc tracker OpenTheRank và trạng thái công khai @thsottiaux trên X mỗi 15 phút. Tỷ lệ hôm nay là ước tính từ lịch sử + tín hiệu X; không dữ liệu tài khoản nào được gửi ra ngoài.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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

