import Foundation
import LocalAuthentication

enum AppLockKeys {
    // Namespaced and versioned so an app previously installed with the same
    // signing bundle ID cannot accidentally enable Codex Cockpit's lock.
    static let faceIDEnabled = "vn.nam.CodexCockpit.faceIDEnabled.v2"
}

@MainActor
final class AppLockModel: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: AppLockKeys.faceIDEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: AppLockKeys.faceIDEnabled)
            if !newValue { isUnlocked = true }
        }
    }

    func unlockIfNeeded() async {
        guard isEnabled else {
            isUnlocked = true
            return
        }
        await authenticate()
    }

    func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = error?.localizedDescription ?? L10n.text("lock.unavailable")
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: L10n.text("lock.reason")
            )
            isUnlocked = success
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func lockWhenEnabled() {
        if isEnabled { isUnlocked = false }
    }
}
