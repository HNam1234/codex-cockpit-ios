import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            CockpitBackdrop()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 13) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR LIBRARY").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(CockpitTheme.accent)
                        Text("WebKit Profiles").font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Mỗi profile là một phiên ChatGPT độc lập. Đổi mapping không xóa cookie.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)

                    ForEach(mappings.profiles) { profile in
                        let account = store.accounts.first(where: { $0.id == mappings.mappedAccountID(for: profile.id) })
                        Button {
                            if let account { router.profilePath.append(AppRoute.accountDetail(account.id)) }
                        } label: {
                            HStack(spacing: 14) {
                                ProfileArtwork(seed: profile.id, symbol: "safari.fill", size: 58)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name).font(.headline).foregroundStyle(.primary)
                                    Text(account?.identity ?? "Chưa gán tài khoản")
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: account == nil ? "plus.circle" : "chevron.right")
                                    .foregroundStyle(account == nil ? CockpitTheme.accent : .secondary)
                            }
                            .padding(14).glassCard(cornerRadius: 22)
                        }
                        .buttonStyle(.plain).disabled(account == nil)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { mappings.addProfile() } label: {
                    ZStack {
                        Circle().fill(.thinMaterial).frame(width: 36, height: 36)
                        Image(systemName: "plus").font(.subheadline.weight(.bold))
                    }
                }
            }
        }
    }
}
