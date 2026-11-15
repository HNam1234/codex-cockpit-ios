import SwiftUI
import UIKit

struct MailboxDetailView: View {
    let mailboxID: UUID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mailStore: DisposableMailStore
    @EnvironmentObject private var store: CockpitStore
    @EnvironmentObject private var mappings: ProfileMappingStore
    @State private var confirmingDelete = false

    var body: some View {
        ZStack {
            CockpitBackdrop()
            if let mailbox {
                List {
                    mailboxHeader(mailbox)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    Section(L10n.text("mail.inbox.title")) {
                        if messages.isEmpty {
                            ContentUnavailableView(
                                L10n.text("mail.inbox.empty"),
                                systemImage: "tray"
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(messages) { message in
                                NavigationLink {
                                    DisposableMessageView(
                                        mailboxID: mailboxID,
                                        initialMessage: message
                                    )
                                } label: {
                                    messageRow(message)
                                }
                                .accessibilityIdentifier("mail-message-row")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await refresh(force: true) }
            } else {
                ContentUnavailableView(
                    L10n.text("mail.unavailable"),
                    systemImage: "envelope.badge.fill"
                )
            }
        }
        .navigationTitle(L10n.text("mail.inbox.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let mailbox {
                        Button {
                            UIPasteboard.general.string = mailbox.address
                        } label: {
                            Label(L10n.text("mail.copy_address"), systemImage: "doc.on.doc")
                        }
                        if let accountID = mailbox.linkedAccountID {
                            Button { mailStore.unlinkAccount(accountID) } label: {
                                Label(L10n.text("mail.unlink"), systemImage: "link.badge.minus")
                            }
                        }
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label(L10n.text("mail.delete"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            L10n.text("mail.delete_confirmation"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L10n.text("mail.delete"), role: .destructive) {
                Task {
                    await mailStore.delete(mailboxID: mailboxID)
                    if mailStore.mailboxes.allSatisfy({ $0.id != mailboxID }) { dismiss() }
                }
            }
            Button(L10n.text("mail.cancel"), role: .cancel) {}
        }
        .task { await refresh(force: false) }
        .accessibilityIdentifier("mail-inbox")
    }

    private var mailbox: DisposableMailbox? {
        mailStore.mailboxes.first { $0.id == mailboxID }
    }

    private var messages: [DisposableMessage] {
        mailStore.messagesByMailbox[mailboxID] ?? []
    }

    private func mailboxHeader(_ mailbox: DisposableMailbox) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                ProfileArtwork(seed: mailbox.address, symbol: "envelope.fill", size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mailbox.address).font(.headline).textSelection(.enabled)
                    if let accountID = mailbox.linkedAccountID {
                        Text(mappingLabel(accountID))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.text("mail.unlinked"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Label(
                    L10n.format("mail.remaining_days", mailbox.remainingDays()),
                    systemImage: "calendar.badge.clock"
                )
                Spacer()
                Text(L10n.format("mail.unread_count", mailbox.unreadCount))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(CockpitTheme.violet)

            if let lastSync = mailbox.lastSyncedAt {
                Text(L10n.format("mail.last_sync", lastSync.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if mailbox.errorCategory != nil {
                Label(L10n.text("mail.cached"), systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if mailbox.state == .providerUnavailable {
                Button {
                    replace(mailbox)
                } label: {
                    Label(L10n.text("mail.replace"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(CapsuleActionStyle(tint: CockpitTheme.cyan))
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }

    private func messageRow(_ message: DisposableMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(message.seen ? Color.secondary.opacity(0.18) : CockpitTheme.accent)
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(message.subject.isEmpty ? L10n.text("mail.no_subject") : message.subject)
                    .font(.subheadline.weight(message.seen ? .medium : .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(message.senderName ?? message.senderAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !message.intro.isEmpty {
                    Text(message.intro)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Text(message.receivedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    private func mappingLabel(_ accountID: String) -> String {
        if let account = store.account(id: accountID) {
            return "\(mappings.displayIdentity(for: account)) · \(mappings.profile(for: accountID).name)"
        }
        if ProcessInfo.processInfo.environment["PREVIEW_MAIL_SAMPLE"] == "1" {
            return "preview.account@example.com · WebKit 1"
        }
        return accountID
    }

    private func refresh(force: Bool) async {
        guard ProcessInfo.processInfo.environment["UITEST_MODE"] == nil else { return }
        await mailStore.refresh(mailboxID: mailboxID, force: force)
    }

    private func replace(_ oldMailbox: DisposableMailbox) {
        Task {
            if let accountID = oldMailbox.linkedAccountID {
                mailStore.unlinkAccount(accountID)
                _ = await mailStore.create(lifetime: oldMailbox.lifetime, linkedAccountID: accountID)
            } else {
                _ = await mailStore.create(lifetime: oldMailbox.lifetime, linkedAccountID: nil)
            }
        }
    }
}
