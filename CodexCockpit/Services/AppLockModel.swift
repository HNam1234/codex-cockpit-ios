import Foundation
import LocalAuthentication

@MainActor
final class AppLockModel: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "faceIDEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "faceIDEnabled")
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
            errorMessage = error?.localizedDescription ?? "Không dùng được Face ID/mật mã."
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Mở Codex Cockpit và năm phiên tài khoản."
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
