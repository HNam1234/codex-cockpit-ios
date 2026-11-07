import SwiftUI

struct CockpitView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: CockpitStore

    var body: some View {
        Group {
            if ProcessInfo.processInfo.environment["UITEST_MODE"] == "static" {
                Text("Cockpit ready").accessibilityIdentifier("cockpit-ready")
            } else {
                ZStack {
                    CockpitBackdrop()
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            heroHeader
                            if let signal = store.tiboReset { TiboResetBanner(signal: signal) }
                            accountShelf
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                    }
                    .refreshable { await store.load() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await store.load() } } label: {
                    ZStack {
                        Circle().fill(.thinMaterial).frame(width: 36, height: 36)
                        if store.isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise").font(.subheadline.weight(.bold)) }
                    }
                }
                .disabled(store.isLoading)
            }
        }
        .alert("Không thể cập nhật", isPresented: errorBinding) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "Lỗi không xác định") }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CODEX COCKPIT")
                .font(.caption.weight(.bold)).tracking(1.6).foregroundStyle(CockpitTheme.accent)
            Text("Quota của bạn")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(store.accounts.count) tài khoản · cập nhật theo thời gian thực")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var accountShelf: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(title: "Tài khoản", caption: store.accounts.isEmpty ? nil : "Vuốt để xem")
            if store.accounts.isEmpty && store.isLoading {
                ProgressView("Đang tải quota…").frame(maxWidth: .infinity).padding(.vertical, 80)
            } else if store.accounts.isEmpty {
                ContentUnavailableView("Chưa có tài khoản", systemImage: "person.crop.circle.badge.questionmark")
                    .frame(maxWidth: .infinity).glassCard()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(store.accounts) { account in
                            Button { router.showAccount(account.id) } label: {
                                AccountOverviewCard(account: account)
                            }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 14)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}

struct TiboResetBanner: View {
    let signal: TiboResetStatus

    private var colors: [Color] {
        switch signal.status {
        case "yes": [.green, .teal]
        case "likely": [.orange, .pink]
        case "no": [CockpitTheme.violet, .blue]
        default: [.gray, CockpitTheme.violet]
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.18)).frame(width: 160).blur(radius: 3).offset(x: 245, y: -55)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("TIBO SIGNAL", systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.heavy)).tracking(1.2)
                    Spacer()
                    Image(systemName: "sparkles").font(.title3)
                }
                Text(signal.message)
                    .font(.title3.weight(.bold)).lineLimit(3)
                HStack {
                    Text("Feed công khai · không gửi dữ liệu account")
                        .font(.caption2).opacity(0.84)
                    Spacer()
                    if let url = URL(string: signal.source) {
                        Link(destination: url) { Image(systemName: "arrow.up.right.circle.fill").font(.title3) }
                    }
                }
            }
            .foregroundStyle(.white).padding(18)
        }
        .frame(minHeight: 168)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: colors[0].opacity(0.26), radius: 20, y: 10)
    }
}

struct AccountOverviewCard: View {
    let account: AccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                ProfileArtwork(seed: account.id, symbol: account.ok ? "command" : "exclamationmark", size: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.identity).font(.title3.weight(.bold)).lineLimit(1)
                    Text([account.name, account.plan?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
            }

            if let error = account.error, !account.ok {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).lineLimit(2)
            } else {
                VStack(spacing: 14) {
                    ForEach(account.windows.prefix(2)) { window in
                        QuotaProgressRow(window: window, compact: true)
                    }
                }
            }

            HStack {
                Label("Mở chi tiết", systemImage: "play.circle.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(CockpitTheme.accent)
                Spacer()
                Text("LIVE").font(.caption2.weight(.heavy)).tracking(1)
                    .foregroundStyle(account.ok ? .green : .red)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .glassCard(cornerRadius: 28)
    }
}

struct QuotaProgressRow: View {
    let window: QuotaWindow
    var compact = false

    private var color: Color {
        switch window.remainingPercent { case 50...: .green; case 20..<50: .orange; default: CockpitTheme.accent }
    }

    var body: some View {
        VStack(spacing: compact ? 7 : 9) {
            HStack {
                Text(window.label).font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font((compact ? Font.caption : Font.subheadline).monospacedDigit().weight(.heavy))
                    .foregroundStyle(color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.62)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * max(0, min(1, window.remainingPercent / 100)))
                }
            }
            .frame(height: compact ? 7 : 10)
            if !compact {
                HStack {
                    Text("Đã dùng \(Int(window.usedPercent.rounded()))%")
                    Spacer()
                    Text("Reset \(Date(timeIntervalSince1970: TimeInterval(window.resetsAt)).formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
