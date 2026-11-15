import Foundation

struct DisposableMailSnapshot: Codable, Equatable, Sendable {
    var mailboxes: [DisposableMailbox]
    var messagesByMailbox: [UUID: [DisposableMessage]]

    static let empty = DisposableMailSnapshot(mailboxes: [], messagesByMailbox: [:])
}

protocol DisposableMailPersisting: Sendable {
    func load() throws -> DisposableMailSnapshot
    func save(_ snapshot: DisposableMailSnapshot) throws
}

struct DisposableMailPersistence: DisposableMailPersisting, Sendable {
    static let protectedWritingOptions: Data.WritingOptions = [.completeFileProtection]

    private let fileURL: URL
    private let maxMessagesPerMailbox: Int
    private let maxBodyLength: Int
    private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        maxMessagesPerMailbox: Int = 100,
        maxBodyLength: Int = MailTextSanitizer.maximumLength,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.maxMessagesPerMailbox = max(0, maxMessagesPerMailbox)
        self.maxBodyLength = max(0, maxBodyLength)
    }

    func load() throws -> DisposableMailSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .empty }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            return try JSONDecoder().decode(DisposableMailSnapshot.self, from: data)
        } catch {
            try? fileManager.removeItem(at: fileURL)
            return .empty
        }
    }

    func save(_ snapshot: DisposableMailSnapshot) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        let bounded = boundedSnapshot(snapshot)
        let data = try JSONEncoder().encode(bounded)
        let temporaryURL = fileURL.appendingPathExtension("tmp")
        try? fileManager.removeItem(at: temporaryURL)

        do {
            try data.write(to: temporaryURL, options: Self.protectedWritingOptions)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func boundedSnapshot(_ snapshot: DisposableMailSnapshot) -> DisposableMailSnapshot {
        let boundedMessages = snapshot.messagesByMailbox.mapValues { messages in
            messages
                .sorted { $0.receivedAt > $1.receivedAt }
                .prefix(maxMessagesPerMailbox)
                .map { message in
                    DisposableMessage(
                        id: message.id,
                        mailboxID: message.mailboxID,
                        senderName: message.senderName,
                        senderAddress: message.senderAddress,
                        subject: message.subject,
                        intro: message.intro,
                        text: String(message.text.prefix(maxBodyLength)),
                        receivedAt: message.receivedAt,
                        seen: message.seen,
                        attachments: message.attachments
                    )
                }
        }
        return DisposableMailSnapshot(
            mailboxes: snapshot.mailboxes,
            messagesByMailbox: boundedMessages
        )
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("CodexCockpit", isDirectory: true)
            .appendingPathComponent("DisposableMail", isDirectory: true)
            .appendingPathComponent("cache-v1.json")
    }
}
