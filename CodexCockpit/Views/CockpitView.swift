import SwiftUI

struct CockpitView: View {
    @StateObject private var browser = BrowserState()
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack(alignment: .top) {
            let testMode = ProcessInfo.processInfo.environment["UITEST_MODE"]
            if testMode == "static" {
                Text("Cockpit ready")
                    .accessibilityIdentifier("cockpit-ready")
            } else {
                ProfileWebView(
                    dataStoreIdentifier: AccountProfile.dashboardDataStoreIdentifier,
                    initialRequest: testMode == "webview"
                        ? URLRequest(url: URL(string: "about:blank")!)
                        : AppURLs.dashboardRequest,
                    state: browser,
                    automaticLoginRequest: testMode == nil ? AppURLs.dashboardRequest : nil,
                    onProfileRoute: { router.open($0) }
                )
                .accessibilityIdentifier("cockpit-webview")
            }

            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .progressViewStyle(.linear)
            }
        }
        .navigationTitle("Codex Cockpit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}
