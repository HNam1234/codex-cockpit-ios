import SwiftUI

struct DirectOAuthSuccessSheet: View {
    let registration: DirectOAuthRegistration
    let showsLiveQuota: Bool
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
                    Text(L10n.text(showsLiveQuota
                        ? "oauth.direct.success.title"
                        : "oauth.direct.success.local.title"))
                        .font(.title3.weight(.bold))
                    Text(registration.email)
                        .font(.headline.monospaced())
                        .foregroundStyle(CockpitTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(L10n.text(showsLiveQuota
                        ? "oauth.direct.success.detail"
                        : "oauth.direct.success.local.detail"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: onContinue) {
                    Label(L10n.text("oauth.direct.success.continue"), systemImage: "safari.fill")
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
