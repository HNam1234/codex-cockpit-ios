import SwiftUI

struct DirectOAuthSuccessSheet: View {
    let registration: DirectOAuthRegistration
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.13))
                        .frame(width: 78, height: 78)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.green)
                }

                VStack(spacing: 6) {
                    Text("Đã kết nối trực tiếp")
                        .font(.title3.weight(.bold))
                    Text(registration.email)
                        .font(.headline.monospaced())
                        .foregroundStyle(CockpitTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("Email đã xác minh này là tên account. Token chỉ lưu trong Keychain cục bộ trên iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: onContinue) {
                    Label("Tiếp tục vào ChatGPT", systemImage: "safari.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.accent))
            }
            .padding(22)
            .navigationTitle("OpenAI OAuth")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
