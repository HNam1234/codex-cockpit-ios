import SwiftUI
import UIKit

struct CockpitOAuthEntrySheet: View {
    let accountName: String
    let identity: String?
    let onOpen: (CockpitOAuthAttempt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rawURL = ""
    @State private var attempt: CockpitOAuthAttempt?
    @State private var validationErrorKey: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    accountCard
                    instructions
                    urlEntry
                    if let validationErrorKey {
                        Label(L10n.text(validationErrorKey), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("cockpit-oauth-error")
                    }
                    Button {
                        guard let attempt else { return }
                        onOpen(attempt)
                        dismiss()
                    } label: {
                        Label(L10n.text("oauth.relay.entry.open"), systemImage: "safari.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.accent))
                    .disabled(attempt == nil)
                    .accessibilityIdentifier("cockpit-oauth-open")
                }
                .padding(20)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cockpit-oauth-entry")
            .navigationTitle(L10n.text("oauth.relay.entry.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("oauth.relay.close")) { dismiss() }
                }
            }
        }
    }

    private var accountCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .foregroundStyle(CockpitTheme.violet)
            VStack(alignment: .leading, spacing: 3) {
                Text(accountName).font(.headline)
                Text(identity ?? L10n.text("oauth.relay.identity.unknown"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("cockpit-oauth-identity")
            }
            Spacer()
            Text("WEBKIT")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(CockpitTheme.accent)
        }
        .padding(14)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("oauth.relay.entry.step_pc"), systemImage: "desktopcomputer")
            Label(L10n.text("oauth.relay.entry.step_copy"), systemImage: "doc.on.doc")
            Label(L10n.text("oauth.relay.entry.step_local"), systemImage: "lock.shield.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var urlEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("oauth.relay.entry.url_label"))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            TextField(L10n.text("oauth.relay.entry.url_placeholder"), text: $rawURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(.footnote, design: .monospaced))
                .padding(12)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("cockpit-oauth-url-field")
                .onChange(of: rawURL) { _, value in validate(value) }
            Button {
                rawURL = UIPasteboard.general.string ?? ""
            } label: {
                Label(L10n.text("oauth.relay.entry.paste"), systemImage: "doc.on.clipboard")
            }
            .font(.subheadline.weight(.bold))
        }
    }

    private func validate(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            attempt = nil
            validationErrorKey = nil
            return
        }
        do {
            attempt = try CockpitOAuthRelay.prepare(value)
            validationErrorKey = nil
        } catch let error as CockpitOAuthRelayError {
            attempt = nil
            validationErrorKey = error.localizationKey
        } catch {
            attempt = nil
            validationErrorKey = CockpitOAuthRelayError.invalidAuthorizationURL.localizationKey
        }
    }
}

struct CockpitOAuthResultSheet: View {
    let callback: CockpitOAuthCallback
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label(L10n.text("oauth.relay.result.ready"), systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(L10n.text("oauth.relay.result.instruction"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(callback.url.absoluteString)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    UIPasteboard.general.string = callback.url.absoluteString
                    copied = true
                } label: {
                    Label(
                        L10n.text(copied ? "oauth.relay.result.copied" : "oauth.relay.result.copy"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.accent))
                .accessibilityIdentifier("cockpit-oauth-copy")
                Button(role: .destructive) {
                    onClear()
                    dismiss()
                } label: {
                    Text(L10n.text("oauth.relay.result.clear"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cockpit-oauth-clear")
                Spacer()
            }
            .padding(20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cockpit-oauth-result")
            .navigationTitle(L10n.text("oauth.relay.result.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
