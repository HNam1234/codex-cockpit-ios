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
                        LazyVStack(alignment: .leading, spacing: 13) {
                            heroHeader
                            if let signal = store.tiboReset { TiboResetBanner(signal: signal) }
                            accountShelf
                        }
                        .padding(.horizontal, 13).padding(.bottom, 18)
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
                        Circle().fill(.thinMaterial).frame(width: 34, height: 34)
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
        VStack(alignment: .leading, spacing: 3) {
            Text("CODEX COCKPIT")
                .font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(CockpitTheme.accent)
            Text("Quota của bạn").font(.system(size: 29, weight: .bold, design: .rounded))
            Text("\(store.accounts.count) tài khoản · realtime")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 3)
    }

    @ViewBuilder
    private var accountShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "Tài khoản", caption: store.accounts.isEmpty ? nil : "HIỂN THỊ TẤT CẢ")
            if store.accounts.isEmpty && store.isLoading {
                ProgressView("Đang tải quota…").frame(maxWidth: .infinity).padding(.vertical, 60)
            } else if store.accounts.isEmpty {
                ContentUnavailableView("Chưa có tài khoản", systemImage: "person.crop.circle.badge.questionmark")
                    .frame(maxWidth: .infinity).glassCard()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(store.accounts) { account in
                        Button { router.showAccount(account.id) } label: {
                            AccountOverviewCard(account: account)
                        }
                        .buttonStyle(.plain)
                    }
                }
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
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.15)).frame(width: 120).blur(radius: 4).offset(x: 145, y: -35)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("TIBO ON X", systemImage: "waveform.path.ecg")
                        .font(.caption2.weight(.heavy)).tracking(1.1)
                    if let post = signal.hintPost {
                        Text("“\(post.text)”").font(.headline.weight(.bold)).lineLimit(2)
                        if let url = URL(string: post.url) {
                            Link("@thsottiaux · mở trên X", destination: url)
                                .font(.caption2.weight(.semibold)).opacity(0.86)
                        }
                    } else {
                        Text(signal.message).font(.subheadline.weight(.bold)).lineLimit(2)
                    }
                }
                Spacer(minLength: 2)
                VStack(spacing: 3) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.22), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(signal.probabilityToday ?? 0) / 100)
                            .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(signal.probabilityToday ?? 0)%")
                            .font(.headline.monospacedDigit().weight(.heavy))
                    }
                    .frame(width: 56, height: 56)
                    Text("RESET HÔM NAY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                }
            }
            .foregroundStyle(.white).padding(13)
        }
        .frame(height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: colors[0].opacity(0.22), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TIBO: \(signal.hintPost?.text ?? signal.message). Xác suất reset hôm nay \(signal.probabilityToday ?? 0) phần trăm")
    }
}

struct AccountOverviewCard: View {
    let account: AccountSnapshot

    var body: some View {
        HStack(spacing: 9) {
            ProfileArtwork(seed: account.id, symbol: account.ok ? "command" : "exclamationmark", size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.identity).font(.subheadline.weight(.bold)).lineLimit(1)
                Text([account.name, account.plan?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: 112, alignment: .leading)
            Spacer(minLength: 2)
            if account.ok {
                VStack(spacing: 6) {
                    ForEach(account.windows.prefix(2)) { window in MiniQuotaRow(window: window) }
                }
                .frame(width: 132)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 63)
        .glassCard(cornerRadius: 18)
    }
}

private struct MiniQuotaRow: View {
    let window: QuotaWindow

    private var color: Color {
        switch window.remainingPercent { case 50...: .green; case 20..<50: .orange; default: CockpitTheme.accent }
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(window.label).font(.system(size: 9, weight: .bold)).lineLimit(1)
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: proxy.size.width * max(0, min(1, window.remainingPercent / 100)))
                }
            }
            .frame(height: 4)
        }
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
