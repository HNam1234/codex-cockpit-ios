import SwiftUI

struct RootView: View {
    @StateObject private var router = AppRouter()
    @StateObject private var directory = AccountDirectory()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack { CockpitView() }
                .tabItem { Label("Cockpit", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(AppTab.cockpit)

            NavigationStack(path: $router.accountPath) {
                AccountsView()
                    .navigationDestination(for: ProfileRoute.self) { route in
                        ProfileDetailView(profile: directory.profile(id: route.id), initialAction: route.action)
                    }
            }
                .tabItem { Label("Tài khoản", systemImage: "person.3.fill") }
                .tag(AppTab.accounts)

            NavigationStack { SettingsView() }
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(.blue)
        .environmentObject(router)
        .environmentObject(directory)
        .task { await directory.refresh() }
    }
}
