import Combine
import Foundation
import UserNotifications

@MainActor
final class TiboNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var permissionDenied = false

    private let enabledKey = "CodexCockpit.tiboNotifications.enabled.v1"
    private let historyKey = "CodexCockpit.tiboNotifications.history.v1"
    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private var pendingIdentifiers: Set<String> = []
    private var history: TiboAlertHistory

    init(
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.center = center
        if let data = defaults.data(forKey: historyKey),
           let restored = try? JSONDecoder().decode(TiboAlertHistory.self, from: data) {
            history = restored
        } else {
            history = TiboAlertHistory()
        }
        isEnabled = defaults.bool(forKey: enabledKey)
        super.init()
        center.delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled else {
            isEnabled = false
            permissionDenied = false
            defaults.set(false, forKey: enabledKey)
            return
        }

        isRequestingPermission = true
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            isRequestingPermission = false
            isEnabled = granted
            permissionDenied = !granted
            defaults.set(granted, forKey: enabledKey)
        }
    }

    func process(_ signal: TiboResetStatus?) {
        guard isEnabled,
              let signal,
              let alert = TiboAlertPolicy.content(for: signal),
              !history.contains(alert.identifier),
              pendingIdentifiers.insert(alert.identifier).inserted else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.userInfo = ["kind": "tibo", "signal": signal.status]

        center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingIdentifiers.remove(alert.identifier)
                if error == nil, self.history.insert(alert.identifier),
                   let data = try? JSONEncoder().encode(self.history) {
                    self.defaults.set(data, forKey: self.historyKey)
                }
            }
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        guard isEnabled else { return }
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            permissionDenied = false
        default:
            isEnabled = false
            permissionDenied = settings.authorizationStatus == .denied
            defaults.set(false, forKey: enabledKey)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
