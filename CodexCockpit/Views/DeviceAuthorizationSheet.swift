import SwiftUI
import UIKit

struct DeviceAuthorizationSheet: View {
    let accountID: String
    let accountName: String
    var previewSession: LoginSession? = nil
    let onOpen: (LoginSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CockpitStore
    @State private var copied = false

    private var session: LoginSession? { previewSession ?? store.loginSessions[accountID] }

    var body: some View {
        NavigationStack {
            ZStack {
                CockpitBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        authorizationCard
                        privacyNote
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Đăng nhập nhanh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .task(id: accountID) { await startIfNeeded() }
        .onChange(of: session?.userCode, initial: true) { _, code in
            guard let code, !code.isEmpty else { return }
            UIPasteboard.general.string = code
            copied = true
        }
        .onChange(of: session?.status) { _, status in
            guard status == "succeeded" else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(850))
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            ProfileArtwork(seed: accountID, symbol: "key.horizontal.fill", size: 72)
            Text(accountName).font(.title3.weight(.bold)).lineLimit(1)
            Text("Mã này chỉ dành cho WebKit của account trên")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var authorizationCard: some View {
        VStack(spacing: 16) {
            if let session {
                statusHeader(session)
                if let code = session.userCode, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)

                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = code
                            copied = true
                        } label: {
                            Label(copied ? "Đã sao chép" : "Sao chép", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(QuickDeviceActionStyle(tint: .blue))

                        Button {
                            dismiss()
                            DispatchQueue.main.async { onOpen(session) }
                        } label: {
                            Label("Mở WebKit", systemImage: "safari.fill")
                        }
                        .buttonStyle(QuickDeviceActionStyle(tint: CockpitTheme.violet))
                    }
                }

                if session.status == "failed" || session.expiresAt <= Int(Date.now.timeIntervalSince1970) {
                    Button {
                        Task { await store.beginReauthorization(accountID: accountID) }
                    } label: {
                        Label("Tạo mã mới", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.accent))
                }

                if let error = session.error, !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } else {
                ProgressView("Đang lấy device code…")
                    .frame(maxWidth: .infinity).padding(.vertical, 34)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private func statusHeader(_ session: LoginSession) -> some View {
        HStack(spacing: 9) {
            Image(systemName: statusIcon(session.status))
                .foregroundStyle(statusColor(session.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle(session.status)).font(.subheadline.weight(.bold))
                if session.status != "succeeded" {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(expirationText(session.expiresAt, now: context.date))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if session.status != "succeeded" && session.status != "failed" {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var privacyNote: some View {
        Label(
            "App tự kiểm tra trạng thái mỗi 2 giây. Cookie vẫn nằm trong sandbox WebKit và không được gửi lên VPS.",
            systemImage: "lock.shield.fill"
        )
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }

    private func startIfNeeded() async {
        guard previewSession == nil else { return }
        let now = Int(Date.now.timeIntervalSince1970)
        if let session,
           session.status != "succeeded",
           session.status != "failed",
           session.expiresAt > now {
            return
        }
        await store.beginReauthorization(accountID: accountID)
    }

    private func statusTitle(_ status: String) -> String {
        switch status {
        case "succeeded": "Đăng nhập thành công"
        case "failed": "Không thể đăng nhập"
        case "expired": "Mã đã hết hạn"
        default: "Đang chờ xác nhận"
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "succeeded": "checkmark.circle.fill"
        case "failed", "expired": "xmark.circle.fill"
        default: "clock.badge.checkmark.fill"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "succeeded": .green
        case "failed", "expired": .red
        default: CockpitTheme.violet
        }
    }

    private func expirationText(_ expiresAt: Int, now: Date) -> String {
        let remaining = max(0, expiresAt - Int(now.timeIntervalSince1970))
        return remaining > 0
            ? "Mã còn hiệu lực \(remaining / 60):\(String(format: "%02d", remaining % 60))"
            : "Mã đã hết hạn"
    }
}

private struct QuickDeviceActionStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(configuration.isPressed ? 0.2 : 0.11), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
