import SwiftUI
import UIKit

struct MailView: View {
    @EnvironmentObject private var mailStore: DisposableMailStore
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @State private var showingCreate = false
    @State private var pendingDelete: DisposableMailbox?

    var body: some View {
        ZStack {
            CockpitBackdrop()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    header
                    if mailStore.activeMailboxes.isEmpty {
                        emptyState
                    } else {
                        ForEach(mailStore.activeMailboxes) { mailbox in
                            mailboxCard(mailbox)
                        }
                    }
                    providerAttribution
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 28)
                .animation(.snappy(duration: 0.22), value: mailStore.activeMailboxes)
            }
            .scrollBounceBehavior(.always)
            .refreshable { await refreshAll(force: true) }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: {
                    ZStack {
                        Circle().fill(.thinMaterial).frame(width: 36, height: 36)
                        Image(systemName: "plus").font(.subheadline.weight(.bold))
                    }
                }
                .accessibilityIdentifier("mail-create")
                .accessibilityLabel(L10n.text("mail.create.action"))
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateMailboxSheet(accounts: availableAccounts) { lifetime, accountID in
                let mailbox = await mailStore.create(lifetime: lifetime, linkedAccountID: accountID)
                return mailbox != nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            L10n.text("mail.delete_confirmation"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let mailbox = pendingDelete {
                Button(L10n.text("mail.delete"), role: .destructive) {
                    pendingDelete = nil
                    Task { await mailStore.delete(mailboxID: mailbox.id) }
                }
            }
            Button(L10n.text("mail.cancel"), role: .cancel) { pendingDelete = nil }
        }
        .alert(L10n.text("mail.unavailable"), isPresented: errorBinding) {
            Button("OK") { mailStore.dismissError() }
        } message: {
            Text(mailStore.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MAIL COCKPIT")
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(CockpitTheme.cyan)
            Text(L10n.text("mail.title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(L10n.text("mail.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ProfileArtwork(seed: "temporary-mail", symbol: "envelope.badge.fill", size: 76)
            VStack(spacing: 6) {
                Text(L10n.text("mail.empty.title")).font(.headline)
                Text(L10n.text("mail.empty.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { showingCreate = true } label: {
                Label(L10n.text("mail.create.action"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.cyan))
        }
        .padding(22)
        .glassCard()
        .accessibilityIdentifier("mail-empty")
    }

    private func mailboxCard(_ mailbox: DisposableMailbox) -> some View {
        NavigationLink(value: mailbox.id) {
            HStack(spacing: 13) {
                ProfileArtwork(seed: mailbox.address, symbol: "envelope.fill", size: 54)
                VStack(alignment: .leading, spacing: 5) {
                    Text(mailbox.address)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let mapping = mappingLabel(for: mailbox) {
                        Text(mapping)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(L10n.text("mail.unlinked"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        HStack(spacing: 8) {
                            Label(
                                L10n.format("mail.remaining_days", mailbox.remainingDays(at: context.date)),
                                systemImage: "calendar.badge.clock"
                            )
                            if mailbox.unreadCount > 0 {
                                Text(L10n.format("mail.unread_count", mailbox.unreadCount))
                                    .foregroundStyle(CockpitTheme.accent)
                            }
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CockpitTheme.violet)
                    }
                    if mailbox.errorCategory != nil {
                        Label(
                            L10n.text(mailbox.state == .providerUnavailable ? "mail.unavailable" : "mail.cached"),
                            systemImage: "wifi.slash"
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if mailStore.busyMailboxIDs.contains(mailbox.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 21)
        .contextMenu {
            Button { UIPasteboard.general.string = mailbox.address } label: {
                Label(L10n.text("mail.copy_address"), systemImage: "doc.on.doc")
            }
            if let accountID = mailbox.linkedAccountID {
                Button { mailStore.unlinkAccount(accountID) } label: {
                    Label(L10n.text("mail.unlink"), systemImage: "link.badge.minus")
                }
            }
            Button(role: .destructive) { pendingDelete = mailbox } label: {
                Label(L10n.text("mail.delete"), systemImage: "trash")
            }
        }
        .accessibilityIdentifier("mail-card")
    }

    private var providerAttribution: some View {
        Label(L10n.text("mail.provider.attribution"), systemImage: "shield.lefthalf.filled")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .accessibilityIdentifier("mail-attribution")
    }

    private var availableAccounts: [MailAccountOption] {
        let linked = Set(mailStore.activeMailboxes.compactMap(\.linkedAccountID))
        return store.accounts
            .filter { !linked.contains($0.id) }
            .map { account in
                MailAccountOption(
                    id: account.id,
                    identity: mappings.displayIdentity(for: account),
                    webKit: mappings.profile(for: account.id).name
                )
            }
    }

    private func mappingLabel(for mailbox: DisposableMailbox) -> String? {
        guard let accountID = mailbox.linkedAccountID else { return nil }
        if let account = store.account(id: accountID) {
            return "\(mappings.displayIdentity(for: account)) · \(mappings.profile(for: accountID).name)"
        }
        if ProcessInfo.processInfo.environment["PREVIEW_MAIL_SAMPLE"] == "1" {
            return "preview.account@example.com · WebKit 1"
        }
        return accountID
    }

    private func refreshAll(force: Bool) async {
        guard ProcessInfo.processInfo.environment["UITEST_MODE"] == nil else { return }
        for mailbox in mailStore.activeMailboxes {
            await mailStore.refresh(mailboxID: mailbox.id, force: force)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { mailStore.errorMessage != nil },
            set: { if !$0 { mailStore.dismissError() } }
        )
    }
}

struct MailAccountOption: Identifiable, Hashable {
    let id: String
    let identity: String
    let webKit: String
}

private struct CreateMailboxSheet: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [MailAccountOption]
    let create: (MailboxLifetime, String?) async -> Bool
    @State private var lifetime = MailboxLifetime.default
    @State private var accountID: String?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("mail.lifetime.title")) {
                    HStack(spacing: 12) {
                        lifetimeButton(.thirtyDays, key: "mail.lifetime.30")
                        lifetimeButton(.sixtyDays, key: "mail.lifetime.60")
                    }
                    Text(L10n.text("mail.lifetime.notice"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section(L10n.text("mail.link.account")) {
                    Button {
                        accountID = nil
                    } label: {
                        selectionRow(title: L10n.text("mail.unlinked"), subtitle: nil, selected: accountID == nil)
                    }
                    .buttonStyle(.plain)
                    ForEach(accounts) { account in
                        Button { accountID = account.id } label: {
                            selectionRow(
                                title: account.identity,
                                subtitle: account.webKit,
                                selected: accountID == account.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(L10n.text("mail.create.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("mail.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("mail.create.confirm")) {
                        isCreating = true
                        Task {
                            if await create(lifetime, accountID) { dismiss() }
                            isCreating = false
                        }
                    }
                    .disabled(isCreating)
                }
            }
        }
        .accessibilityIdentifier("mail-create-sheet")
    }

    private func lifetimeButton(_ value: MailboxLifetime, key: String) -> some View {
        Button { lifetime = value } label: {
            HStack {
                Text(L10n.text(key)).font(.subheadline.weight(.bold))
                Spacer()
                Image(systemName: lifetime == value ? "checkmark.circle.fill" : "circle")
            }
            .foregroundStyle(lifetime == value ? CockpitTheme.cyan : .secondary)
            .padding(12)
            .background(CockpitTheme.cyan.opacity(lifetime == value ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(value == .sixtyDays ? "mail-lifetime-60" : "mail-lifetime-30")
        .accessibilityValue(lifetime == value ? "selected" : "not selected")
    }

    private func selectionRow(title: String, subtitle: String?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(CockpitTheme.cyan) }
        }
        .contentShape(Rectangle())
    }
}
