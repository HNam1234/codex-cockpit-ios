import Foundation

enum MailboxLifetime: Int, Codable, CaseIterable, Hashable, Sendable {
    case thirtyDays = 30
    case sixtyDays = 60

    static let `default`: MailboxLifetime = .sixtyDays

    func expiry(from start: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: rawValue, to: start)
            ?? start.addingTimeInterval(TimeInterval(rawValue * 86_400))
    }
}

enum DisposableMailboxState: String, Codable, Hashable, Sendable {
    case active
    case expired
    case pendingDeletion
    case providerUnavailable
    case deleted
}

enum DisposableMailErrorCategory: String, Codable, Hashable, Sendable {
    case offline
    case provider
    case authentication
    case missing
    case rateLimited
}

struct DisposableMailbox: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let providerAccountID: String
    let address: String
    let createdAt: Date
    let expiresAt: Date
    let lifetime: MailboxLifetime
    var linkedAccountID: String?
    var state: DisposableMailboxState
    var unreadCount: Int
    var lastSyncedAt: Date?
    var errorCategory: DisposableMailErrorCategory?

    func remainingDays(at now: Date = .now) -> Int {
        let remaining = expiresAt.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return max(1, Int(ceil(remaining / 86_400)))
    }

    func isExpired(at now: Date = .now) -> Bool {
        expiresAt <= now
    }
}

struct DisposableAttachment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let fileName: String
    let mediaType: String
    let size: Int
}

struct DisposableMessage: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let mailboxID: UUID
    let senderName: String?
    let senderAddress: String
    let subject: String
    let intro: String
    let text: String
    let receivedAt: Date
    var seen: Bool
    let attachments: [DisposableAttachment]
}
