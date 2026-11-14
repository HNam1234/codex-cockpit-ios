import SwiftUI
import UIKit

struct PCDeviceCodeSheet: View {
    let accountID: String
    let accountName: String
    var previewCode: String? = nil
    let onOpen: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFieldFocused: Bool
    @State private var code = ""

    private var normalizedCode: String {
        DeviceCodeAssistant.normalized(code)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CockpitBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        instructionsCard
                        codeCard
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Nhập code từ PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .onAppear {
            if let previewCode {
                code = DeviceCodeAssistant.normalized(previewCode)
            } else {
                codeFieldFocused = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            ProfileArtwork(seed: accountID, symbol: "desktopcomputer", size: 72)
            Text(accountName).font(.title3.weight(.bold)).lineLimit(1)
            Text("Code sẽ được điền vào WebKit riêng của account này")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            instructionRow(number: 1, text: "Trên PC chạy codex login --device-auth")
            Divider().opacity(0.5)
            instructionRow(number: 2, text: "Copy Device Code mà PC hiển thị")
            Divider().opacity(0.5)
            instructionRow(number: 3, text: "App tự điền và gửi code trong WebKit")
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var codeCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal.fill")
                    .foregroundStyle(CockpitTheme.violet)
                TextField("ABCD-EFGH", text: $code)
                    .focused($codeFieldFocused)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .submitLabel(.go)
                    .onChange(of: code) { _, value in
                        let normalized = DeviceCodeAssistant.normalized(value)
                        if value != normalized { code = normalized }
                    }
                    .onSubmit { openWebKit() }
                Button {
                    code = DeviceCodeAssistant.normalized(UIPasteboard.general.string ?? "")
                } label: {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Dán code từ clipboard")
            }
            .padding(14)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))

            Button(action: openWebKit) {
                Label("Tiếp tục tự động", systemImage: "wand.and.stars")
            }
            .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.violet))
            .disabled(normalizedCode.isEmpty)
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(spacing: 11) {
            Text("\(number)")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(CockpitTheme.violet, in: Circle())
            Text(text).font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    private func openWebKit() {
        let normalized = normalizedCode
        guard !normalized.isEmpty else { return }
        dismiss()
        DispatchQueue.main.async { onOpen(normalized) }
    }
}
