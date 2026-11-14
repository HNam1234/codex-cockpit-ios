import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @EnvironmentObject private var router: AppRouter
    @State private var showingAddAccount = false
    @State private var pendingDelete: AccountSnapshot?

    var body: some View {
        ZStack {
            CockpitBackdrop()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    header
                    if store.accounts.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.accounts) { account in accountCard(account) }
                    }
                    addAccountButton
                }
                .padding(.horizontal, 14).padding(.bottom, 28)
                .animation(.snappy(duration: 0.22), value: store.accounts.map(\.id))
            }
            .scrollBounceBehavior(.always)
            .refreshable { await store.load() }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddAccount = true } label: {
                    ZStack {
                        Circle().fill(.thinMaterial).frame(width: 36, height: 36)
                        Image(systemName: "plus").font(.subheadline.weight(.bold))
                    }
                }
                .accessibilityLabel("Thêm tài khoản")
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            NewAccountSheet(isCreating: store.isCreatingAccount) { name in
                Task { await createAndOpenAccount(name: name) }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Xóa \(pendingDelete.map { mappings.displayIdentity(for: $0) } ?? "tài khoản")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let account = pendingDelete {
                Button("Xóa account và WebKit", role: .destructive) {
                    pendingDelete = nil
                    Task { await delete(account) }
                }
            }
            Button("Hủy", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Credential trên VPS sẽ được archive để có thể khôi phục. Cookie WebKit trên iPhone sẽ bị xóa.")
        }
        .alert("Không thể hoàn tất", isPresented: errorBinding) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Lỗi không xác định")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ACCOUNT COCKPIT")
                .font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(CockpitTheme.accent)
            Text("Tài khoản & WebKit").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Mỗi account có đúng một WebKit riêng. Cookie và phiên đăng nhập không dùng chung.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 5)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Chưa có tài khoản", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Thêm account để tạo WebKit riêng và lấy device code đăng nhập.")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30).glassCard()
    }

    private func accountCard(_ account: AccountSnapshot) -> some View {
        let profile = mappings.profile(for: account.id)
        let busy = store.busyAccounts.contains(account.id)
        return VStack(spacing: 11) {
            Button { router.profilePath.append(AppRoute.accountDetail(account.id)) } label: {
                HStack(spacing: 12) {
                    ProfileArtwork(seed: profile.id, symbol: "safari.fill", size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mappings.displayIdentity(for: account))
                            .font(.headline).foregroundStyle(.primary).lineLimit(1)
                        Text("\(profile.name) · \(account.plan?.uppercased() ?? "CHƯA ĐĂNG NHẬP")")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let remaining = account.subscriptionRemainingText() {
                            Text(remaining)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(account.subscriptionIsExpired() ? .red : CockpitTheme.violet)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 4)
                    if busy {
                        ProgressView().controlSize(.small)
                    } else if account.ok, !account.windows.isEmpty {
                        AccountQuotaSnapshot(windows: Array(account.windows.prefix(2)))
                            .frame(width: 105)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().opacity(0.55)

            HStack(spacing: 8) {
                Button { router.openBrowser(accountID: account.id) } label: {
                    Label("Mở WebKit", systemImage: "safari.fill")
                }
                .buttonStyle(CompactAccountActionStyle(tint: .blue))

                Button { Task { await openDeviceCode(for: account.id) } } label: {
                    Label("Device code", systemImage: "key.horizontal.fill")
                }
                .buttonStyle(CompactAccountActionStyle(tint: CockpitTheme.violet))
                .disabled(busy)

                Button(role: .destructive) { pendingDelete = account } label: {
                    Image(systemName: "trash.fill").frame(width: 16)
                }
                .buttonStyle(CompactAccountActionStyle(tint: .red))
                .disabled(busy)
                .accessibilityLabel("Xóa \(account.name)")
            }
        }
        .padding(13).glassCard(cornerRadius: 21)
    }

    private var addAccountButton: some View {
        Button { showingAddAccount = true } label: {
            Label("Thêm account + WebKit", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 13)
        }
        .buttonStyle(.plain).foregroundStyle(CockpitTheme.accent)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func createAndOpenAccount(name: String) async {
        guard let account = await store.createAccount(name: name) else { return }
        mappings.createDedicatedProfile(for: account.id)
        showingAddAccount = false
        await openDeviceCode(for: account.id)
    }

    private func openDeviceCode(for accountID: String) async {
        guard let session = await store.beginReauthorization(accountID: accountID),
              session.status != "failed" else { return }
        router.openBrowser(
            accountID: accountID,
            launch: BrowserLaunch(
                mode: .device,
                code: session.userCode,
                verificationURL: session.verificationURL
            )
        )
    }

    private func delete(_ account: AccountSnapshot) async {
        let profile = mappings.profile(for: account.id)
        guard await store.deleteAccount(accountID: account.id) else { return }
        mappings.removeAccount(account.id)
        try? await ProfileDataStore.clear(identifier: profile.dataStoreIdentifier)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}

private struct NewAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let isCreating: Bool
    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("Account mới sẽ có một WebKit và cookie store riêng.", systemImage: "square.stack.3d.up.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Tên gợi nhớ (không bắt buộc)", text: $name)
                    .textInputAutocapitalization(.words)
                    .padding(13)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                Button {
                    onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    HStack {
                        if isCreating { ProgressView().tint(.white) }
                        Label("Tạo và lấy device code", systemImage: "key.horizontal.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.accent))
                .disabled(isCreating)
                Text("Mã sẽ được copy, tự điền trong WebKit và giữ lại trên thanh hỗ trợ. Bạn chỉ cần xác nhận trên trang OpenAI.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Thêm tài khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }.disabled(isCreating)
                }
            }
        }
    }
}

private struct CompactAccountActionStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold)).foregroundStyle(tint)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AccountQuotaSnapshot: View {
    let windows: [QuotaWindow]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(windows) { window in
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        Text(window.label)
                            .font(.system(size: 9, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(Int(window.remainingPercent.rounded()))%")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(color(for: window.remainingPercent))
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.secondary.opacity(0.12))
                            Capsule().fill(color(for: window.remainingPercent))
                                .frame(
                                    width: proxy.size.width
                                        * max(0, min(1, window.remainingPercent / 100))
                                )
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(for remaining: Double) -> Color {
        switch remaining {
        case 50...: .green
        case 20..<50: .orange
        default: CockpitTheme.accent
        }
    }
}
