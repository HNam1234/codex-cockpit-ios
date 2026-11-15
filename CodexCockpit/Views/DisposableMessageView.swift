import SwiftUI
import UIKit

struct DisposableMessageView: View {
    let mailboxID: UUID
    let initialMessage: DisposableMessage
    @EnvironmentObject private var mailStore: DisposableMailStore
    @State private var message: DisposableMessage

    init(mailboxID: UUID, initialMessage: DisposableMessage) {
        self.mailboxID = mailboxID
        self.initialMessage = initialMessage
        _message = State(initialValue: initialMessage)
    }

    var body: some View {
        ZStack {
            CockpitBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message.subject.isEmpty ? L10n.text("mail.no_subject") : message.subject)
                            .font(.title2.weight(.bold))
                        LabeledContent(L10n.text("mail.message.from")) {
                            Text(message.senderName ?? message.senderAddress)
                                .multilineTextAlignment(.trailing)
                        }
                        Text(message.senderAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .glassCard()

                    if !codes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: L10n.text("mail.codes.title"))
                            ForEach(codes, id: \.self) { code in
                                Button {
                                    UIPasteboard.general.string = code
                                } label: {
                                    HStack {
                                        Text(code)
                                            .font(.title3.monospaced().weight(.bold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Label(L10n.text("mail.code.copy"), systemImage: "doc.on.doc")
                                            .font(.caption.weight(.bold))
                                    }
                                    .padding(13)
                                    .background(CockpitTheme.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("mail-code-\(code)")
                            }
                        }
                        .padding(18)
                        .glassCard()
                    }

                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .glassCard()

                    if !message.attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: L10n.text("mail.attachments.title"))
                            ForEach(message.attachments) { attachment in
                                HStack(spacing: 10) {
                                    Image(systemName: "paperclip")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(attachment.fileName).font(.subheadline.weight(.semibold))
                                        Text("\(attachment.mediaType) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Text(L10n.text("mail.settings.privacy"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .glassCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(L10n.text("mail.inbox.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            guard ProcessInfo.processInfo.environment["UITEST_MODE"] == nil else { return }
            if let loaded = await mailStore.loadMessage(mailboxID: mailboxID, messageID: initialMessage.id) {
                message = loaded
            }
        }
        .accessibilityIdentifier("mail-message-detail")
    }

    private var codes: [String] {
        VerificationCodeExtractor.codes(subject: message.subject, body: message.text)
    }
}
