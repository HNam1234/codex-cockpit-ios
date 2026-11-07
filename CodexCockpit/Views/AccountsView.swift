import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var directory: AccountDirectory

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(directory.profiles) { profile in
                    NavigationLink(value: ProfileRoute(id: profile.id, action: .web)) {
                        AccountCard(profile: profile)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tài khoản Codex")
        .refreshable { await directory.refresh() }
    }
}

private struct AccountCard: View {
    let profile: AccountProfile

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(profile.tint.opacity(0.15))
                Text(profile.id).font(.headline).foregroundStyle(profile.tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.headline)
                Text("Profile WebKit riêng · giữ session độc lập")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.separator.opacity(0.35)))
    }
}
