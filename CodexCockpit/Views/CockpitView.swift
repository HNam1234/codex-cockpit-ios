import SwiftUI

struct CockpitView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var store: CockpitStore

    var body: some View {
        Group {
            if ProcessInfo.processInfo.environment["UITEST_MODE"] == "static" {
                Text("Cockpit ready").accessibilityIdentifier("cockpit-ready")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let signal = store.tiboReset { TiboResetBanner(signal: signal) }
                        if store.accounts.isEmpty && store.isLoading {
                            ProgressView("Đang tải quota…").padding(.top, 80)
                        } else if store.accounts.isEmpty {
                            ContentUnavailableView("Chưa có tài khoản", systemImage: "person.crop.circle.badge.questionmark")
                        } else {
                            ForEach(store.accounts) { account in
                                Button { router.showAccount(account.id) } label: {
                                    AccountOverviewCard(account: account)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Color(.systemGroupedBackground))
                .refreshable { await store.load() }
            }
        }
        .navigationTitle("Codex Cockpit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await store.load() } } label: {
                    if store.isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(store.isLoading)
            }
        }
        .alert("Không thể cập nhật", isPresented: errorBinding) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "Lỗi không xác định") }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}

struct TiboResetBanner: View {
    let signal: TiboResetStatus

    private var color: Color {
        switch signal.status { case "yes": .green; case "likely": .orange; case "no": .secondary; default: .blue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("TIBO · RESET TOÀN CỤC", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.bold)).foregroundStyle(color)
                Spacer()
                if signal.stale { Text("Dữ liệu cũ").font(.caption2).foregroundStyle(.secondary) }
            }
            Text(signal.message).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            HStack {
                Text("Chỉ đọc feed công khai, không gửi dữ liệu tài khoản.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let url = URL(string: signal.source) {
                    Link("Nguồn", destination: url).font(.caption.weight(.semibold))
                }
            }
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.3)))
    }
}

struct AccountOverviewCard: View {
    let account: AccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(account.ok ? Color.blue.opacity(0.14) : Color.red.opacity(0.14))
                    Image(systemName: account.ok ? "person.fill.checkmark" : "person.fill.xmark")
                        .foregroundStyle(account.ok ? .blue : .red)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.identity).font(.headline).lineLimit(1)
                    Text([account.name, account.plan?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            if let error = account.error, !account.ok {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).lineLimit(2)
            }
            ForEach(account.windows.prefix(2)) { window in
                QuotaProgressRow(window: window, compact: true)
            }
        }
        .padding(13)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.separator.opacity(0.35)))
    }
}

struct QuotaProgressRow: View {
    let window: QuotaWindow
    var compact = false

    private var color: Color {
        switch window.remainingPercent { case 50...: .green; case 20..<50: .orange; default: .red }
    }

    var body: some View {
        VStack(spacing: compact ? 4 : 6) {
            HStack {
                Text(window.label).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% còn lại")
                    .font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(color)
            }
            ProgressView(value: max(0, min(100, window.remainingPercent)), total: 100)
                .tint(color).scaleEffect(x: 1, y: compact ? 1.2 : 1.6)
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
