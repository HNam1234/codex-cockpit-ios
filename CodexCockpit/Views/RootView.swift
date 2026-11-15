import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = AppRouter()
    @StateObject private var store = CockpitStore()
    @StateObject private var mappings = ProfileMappingStore()
    @StateObject private var directOAuth = DirectOAuthStore()
    @StateObject private var tiboNotifications = TiboNotificationManager()
    @StateObject private var identityScanner = WebIdentityScanner()
    @StateObject private var mailStore: DisposableMailStore

    init() {
        let environment = ProcessInfo.processInfo.environment
        let previewSnapshot: DisposableMailSnapshot?
        if environment["PREVIEW_MAIL_SAMPLE"] == "1" {
            previewSnapshot = Self.previewMailSnapshot()
        } else if environment["UITEST_MODE"] != nil {
            previewSnapshot = .empty
        } else {
            previewSnapshot = nil
        }
        _mailStore = StateObject(
            wrappedValue: DisposableMailStore(initialSnapshot: previewSnapshot)
        )
    }

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

            NavigationStack(path: $router.mailPath) {
                MailView()
                    .navigationDestination(for: UUID.self) { mailboxID in
                        MailboxDetailView(mailboxID: mailboxID)
                    }
                    .navigationDestination(for: MailMessagePreviewRoute.self) { route in
                        if let message = mailStore.messagesByMailbox[route.mailboxID]?.first(where: {
                            $0.id == route.messageID
                        }) {
                            DisposableMessageView(
                                mailboxID: route.mailboxID,
                                initialMessage: message
                            )
                        } else {
                            ContentUnavailableView(
                                L10n.text("mail.unavailable"),
                                systemImage: "envelope.badge.fill"
                            )
                        }
                    }
            }
            .tabItem { Label(L10n.text("mail.tab"), systemImage: "envelope.fill") }
            .tag(AppTab.mail)

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
        .environmentObject(mailStore)
        .onAppear {
            directOAuth.restore(profileIDs: mappings.profiles.map(\.id))
            switch ProcessInfo.processInfo.environment["PREVIEW_TAB"] {
            case "profiles": router.selectedTab = .profiles
            case "mail": router.selectedTab = .mail
            case "settings": router.selectedTab = .settings
            default: break
            }
            let environment = ProcessInfo.processInfo.environment
            if environment["PREVIEW_MAIL_OPEN_MESSAGE"] == "1", router.mailPath.isEmpty {
                router.selectedTab = .mail
                let mailboxID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
                router.mailPath.append(mailboxID)
                router.mailPath.append(
                    MailMessagePreviewRoute(mailboxID: mailboxID, messageID: "preview-message")
                )
            } else if environment["PREVIEW_MAIL_OPEN_INBOX"] == "1", router.mailPath.isEmpty {
                router.selectedTab = .mail
                router.mailPath.append(UUID(uuidString: "55555555-5555-4555-8555-555555555555")!)
            }
        }
        .task(id: scenePhase) {
            guard ProcessInfo.processInfo.environment["UITEST_MODE"] == nil,
                  ProcessInfo.processInfo.environment["PREVIEW_MAIL_SAMPLE"] == nil,
                  scenePhase == .active else { return }
            await store.load()
            mappings.synchronize(accounts: store.accounts)
            await mailStore.handleForeground(validAccountIDs: Set(store.accounts.map(\.id)))
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
            guard ProcessInfo.processInfo.environment["UITEST_MODE"] == nil,
                  ProcessInfo.processInfo.environment["PREVIEW_MAIL_SAMPLE"] == nil else { return }
            Task {
                await mailStore.handleForeground(validAccountIDs: Set(store.accounts.map(\.id)))
            }
        }
        .onChange(of: store.tiboReset) { _, signal in
            tiboNotifications.process(signal)
        }
    }

    private static func previewMailSnapshot(now: Date = .now) -> DisposableMailSnapshot {
        let mailboxID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let mailbox = DisposableMailbox(
            id: mailboxID,
            providerAccountID: "preview-provider-account",
            address: "preview@example.test",
            createdAt: now.addingTimeInterval(-8 * 86_400),
            expiresAt: now.addingTimeInterval(52 * 86_400),
            lifetime: .sixtyDays,
            linkedAccountID: "preview-account",
            state: .active,
            unreadCount: 1,
            lastSyncedAt: now,
            errorCategory: nil
        )
        let message = DisposableMessage(
            id: "preview-message",
            mailboxID: mailboxID,
            senderName: "Example Security",
            senderAddress: "security@example.test",
            subject: "Verify your account",
            intro: "Your verification code is ready.",
            text: "Your verification code is 482731. Backup code A9K2.",
            receivedAt: now.addingTimeInterval(-120),
            seen: false,
            attachments: [
                DisposableAttachment(
                    id: "preview-attachment",
                    fileName: "notice.txt",
                    mediaType: "text/plain",
                    size: 128
                )
            ]
        )
        return DisposableMailSnapshot(
            mailboxes: [mailbox],
            messagesByMailbox: [mailboxID: [message]]
        )
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

private struct MailMessagePreviewRoute: Hashable {
    let mailboxID: UUID
    let messageID: String
}
