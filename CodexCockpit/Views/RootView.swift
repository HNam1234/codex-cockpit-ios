import SwiftUI

struct RootView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var store = CockpitStore()
    @StateObject private var mappings = ProfileMappingStore()

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
        .task {
            guard ProcessInfo.processInfo.environment["UITEST_MODE"] == nil else { return }
            await store.load()
        }
        .onChange(of: store.accounts.map(\.id)) { _, _ in
            mappings.synchronize(accounts: store.accounts)
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .accountDetail(let accountID):
            AccountDetailView(accountID: accountID)
        case .browser(let accountID, let launch):
            AccountBrowserView(accountID: accountID, launch: launch)
        }
    }
}
