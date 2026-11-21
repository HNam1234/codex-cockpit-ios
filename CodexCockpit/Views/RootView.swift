import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = AppRouter()
    @StateObject private var store = CockpitStore()
    @StateObject private var mappings = ProfileMappingStore()
    @StateObject private var tiboNotifications = TiboNotificationManager()
    @StateObject private var identityScanner = WebIdentityScanner()
    @StateObject private var credentials = CockpitCredentialModel()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.cockpitPath) {
                CockpitView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(route)
                    }
            }
            .tabItem { Label("Tổng quan", systemImage: "gauge.with.dots.needle.67percent") }
            .tag(AppTab.cockpit)

            NavigationStack(path: $router.profilePath) {
                AccountsView()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(route)
                    }
            }
            .tabItem { Label("WebKit", systemImage: "square.stack.3d.up.fill") }
            .tag(AppTab.profiles)

            NavigationStack { SettingsView() }
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(CockpitTheme.accent)
        .environmentObject(router)
        .environmentObject(store)
        .environmentObject(mappings)
        .environmentObject(tiboNotifications)
        .environmentObject(credentials)
        .task(id: "\(scenePhase)-\(credentials.revision)") {
            guard ProcessInfo.processInfo.environment["UITEST_MODE"] == nil,
                  scenePhase == .active,
                  credentials.isConfigured else { return }
            await store.load()
            mappings.synchronize(accounts: store.accounts)
            prewarmDeviceProfile()
            await identityScanner.scan(profiles: mappings.profiles) { profileID, identity in
                mappings.record(identity: identity, for: profileID, accounts: store.accounts)
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(store.pollSeconds))
                } catch {
                    return
                }
                await store.load()
            }
        }
        .onChange(of: store.accounts) { _, _ in
            mappings.synchronize(accounts: store.accounts)
            prewarmDeviceProfile()
        }
        .onChange(of: store.tiboReset) { _, signal in
            tiboNotifications.process(signal)
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .accountDetail(let accountID):
            AccountDetailView(accountID: accountID)
        case .browser(let accountID, let launch):
            AccountBrowserView(
                accountID: accountID,
                launch: launch,
                profileBinding: BrowserProfileBinding(accountID: accountID, mappings: mappings)
            )
        }
    }

    @MainActor
    private func prewarmDeviceProfile() {
        guard !store.accounts.isEmpty else { return }

        let defaults = UserDefaults.standard
        let lastProfileKey = "CodexCockpit.lastDeviceProfile.v1"
        let profile: WebProfile
        if let profileID = defaults.string(forKey: lastProfileKey),
           mappings.profiles.contains(where: { $0.id == profileID }) {
            profile = mappings.profile(id: profileID)
        } else if let account = (
            store.accounts.first(where: { !$0.ok || $0.error != nil }) ?? store.accounts.first
        ) {
            profile = mappings.profile(for: account.id)
        } else {
            return
        }
        WebViewPool.shared.prewarm(profile: profile)
    }
}
