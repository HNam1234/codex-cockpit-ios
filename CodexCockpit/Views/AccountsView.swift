import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        List {
            Section {
                Text("Mỗi WebKit là một kho cookie riêng. Đổi mapping chỉ đổi tài khoản Codex nào mở profile đó; không xóa phiên ChatGPT.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(mappings.profiles) { profile in
                let account = store.accounts.first(where: { $0.id == mappings.mappedAccountID(for: profile.id) })
                Button {
                    if let account { router.profilePath.append(AppRoute.accountDetail(account.id)) }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(profile.tint.opacity(0.14))
                            Text(profile.id).font(.headline).foregroundStyle(profile.tint)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name).font(.headline).foregroundStyle(.primary)
                            Text(account?.identity ?? "Chưa gán tài khoản")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if account != nil { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                    }
                }
                .disabled(account == nil)
            }
        }
        .navigationTitle("WebKit Profiles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { mappings.addProfile() } label: { Image(systemName: "plus") }
            }
        }
    }
}
