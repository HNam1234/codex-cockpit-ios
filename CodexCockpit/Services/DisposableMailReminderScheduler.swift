import Foundation
import UserNotifications

protocol DisposableMailReminderScheduling: Sendable {
    func schedule(mailbox: DisposableMailbox) async
    func cancel(mailboxID: UUID)
}

protocol DisposableMailNotificationCenterProtocol: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

struct DisposableMailReminderScheduler: DisposableMailReminderScheduling, Sendable {
    private static let reminderDays = [7, 1]

    private let center: any DisposableMailNotificationCenterProtocol
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        center: any DisposableMailNotificationCenterProtocol = SystemDisposableMailNotificationCenter(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.center = center
        self.calendar = calendar
        self.now = now
    }

    func schedule(mailbox: DisposableMailbox) async {
        cancel(mailboxID: mailbox.id)
        guard mailbox.state == .active else { return }

        let status = await center.authorizationStatus()
        guard Self.canSchedule(status) else { return }

        for days in Self.reminderDays {
            guard let fireDate = calendar.date(
                byAdding: .day,
                value: -days,
                to: mailbox.expiresAt
            ), fireDate > now() else { continue }

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString(
                "Temporary mail expires soon",
                comment: "Disposable mailbox expiry reminder title"
            )
            content.body = String(
                format: NSLocalizedString(
                    "A temporary mailbox expires in %d day(s). Open Codex Cockpit to review it.",
                    comment: "Disposable mailbox expiry reminder body"
                ),
                days
            )
            content.sound = .default

            let components = calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifier(mailboxID: mailbox.id, daysBefore: days),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func cancel(mailboxID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: Self.reminderDays.map {
                Self.identifier(mailboxID: mailboxID, daysBefore: $0)
            }
        )
    }

    static func identifier(mailboxID: UUID, daysBefore: Int) -> String {
        "disposable-mail.\(mailboxID.uuidString.lowercased()).\(daysBefore)-days"
    }

    private static func canSchedule(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }
}

struct SystemDisposableMailNotificationCenter: DisposableMailNotificationCenterProtocol {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
