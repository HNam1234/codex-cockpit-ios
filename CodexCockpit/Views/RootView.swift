import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = AppRouter()
    @StateObject private var store = CockpitStore()
    @StateObject private var mappings = ProfileMappingStore()
    @StateObject private var directOAuth = DirectOAuthStore()
    @StateObject private var tiboNotifications = TiboNotificationManager()
    @StateObject private var identityScanner = WebIdentityScanner()

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
        .environmentObject(directOAuth)
        .environmentObject(tiboNotifications)
        .onAppear {
            switch ProcessInfo.processInfo.environment["PREVIEW_TAB"] {
            case "profiles": router.selectedTab = .profiles
            case "settings": router.selectedTab = .settings
            default: break
            }
        }
        .task(id: scenePhase) {
            guard ProcessInfo.processInfo.environment["UITEST_MODE"] == nil,
                  scenePhase == .active else { return }
            await store.load()
            mappings.synchronize(accounts: store.accounts)
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
}
