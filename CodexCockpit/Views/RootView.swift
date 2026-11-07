import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { CockpitView() }
                .tabItem { Label("Cockpit", systemImage: "gauge.with.dots.needle.67percent") }

            NavigationStack { AccountsView() }
                .tabItem { Label("5 tài khoản", systemImage: "person.3.fill") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
        }
        .tint(.blue)
    }
}
