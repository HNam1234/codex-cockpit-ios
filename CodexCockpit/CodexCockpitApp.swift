import SwiftUI

@main
struct CodexCockpitApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appLock = AppLockModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if appLock.isUnlocked {
                    RootView()
                } else {
                    LockView(appLock: appLock)
                }
            }
            .task { await appLock.unlockIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                appLock.lockWhenEnabled()
            }
        }
    }
}
