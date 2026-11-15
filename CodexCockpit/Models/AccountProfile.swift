import CryptoKit
import Foundation
import SwiftUI

struct WebProfile: Identifiable, Hashable, Codable {
    let id: String

    var name: String { "WebKit \(id)" }
    var dataStoreIdentifier: UUID { Self.persistentIdentifier(for: id) }

    var tint: Color {
        let palette: [Color] = [.blue, .cyan, .green, .orange, .purple, .pink, .indigo, .mint]
        let total = id.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) }
        return palette[Int(total % UInt64(palette.count))]
    }

    static func persistentIdentifier(for id: String) -> UUID {
        // These five identifiers shipped in 1.0.x. Never change them: they own the existing cookies.
        if let number = Int(id), (1...5).contains(number) {
            return UUID(uuidString: String(format: "C0D3C%03d-0000-4000-8000-%012d", number, number))!
        }
        let digest = SHA256.hash(data: Data("CodexCockpit.Profile.\(id)".utf8))
        let hex = digest.prefix(16).map { String(format: "%02X", $0) }.joined()
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-8\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value)!
    }
}

struct BrowserProfileBinding: Hashable {
    let profileID: String

    @MainActor
    init(accountID: String, mappings: ProfileMappingStore) {
        profileID = mappings.profile(for: accountID).id
    }

    @MainActor
    func profile(in mappings: ProfileMappingStore) -> WebProfile {
        mappings.profile(id: profileID)
    }
}

struct QuotaWindow: Decodable, Hashable, Identifiable, Sendable {
    let label: String
    let remainingPercent: Double
    let usedPercent: Double
    let resetsAt: Int
    let windowMinutes: Int

    var id: String { "\(label)-\(windowMinutes)-\(resetsAt)" }

    var resetDate: Date {
        Date(timeIntervalSince1970: TimeInterval(resetsAt))
    }

    var localizedLabel: String {
        switch windowMinutes {
        case 300: L10n.text("quota.window.five_hours")
        case 10_080: L10n.text("quota.window.week")
        default: label
        }
    }

    func resetCountdownText(at now: Date = .now, compact: Bool = false) -> String {
        let seconds = Int(resetDate.timeIntervalSince(now))
        guard seconds > 0 else {
            return L10n.text(compact ? "quota.resetting.compact" : "quota.resetting")
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if compact {
            if days > 0 {
                return hours > 0
                    ? L10n.format("quota.compact.days_hours", days, hours)
                    : L10n.format("quota.compact.days", days)
            }
            if hours > 0 {
                return minutes > 0
                    ? L10n.format("quota.compact.hours_minutes", hours, minutes)
                    : L10n.format("quota.compact.hours", hours)
            }
            return L10n.format("quota.compact.minutes", max(1, minutes))
        }
        if days > 0 {
            return hours > 0
                ? L10n.format("quota.reset.days_hours", days, hours)
                : L10n.format("quota.reset.days", days)
        }
        if hours > 0 {
            return minutes > 0
                ? L10n.format("quota.reset.hours_minutes", hours, minutes)
                : L10n.format("quota.reset.hours", hours)
        }
        return L10n.format("quota.reset.minutes", max(1, minutes))
    }

    enum CodingKeys: String, CodingKey {
        case label
        case remainingPercent = "remaining_percent"
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case windowMinutes = "window_minutes"
    }
}

enum AccountHealth: Equatable {
    case needsLogin
    case expired
    case expiring
    case quotaCritical
    case quotaLow
    case healthy

    var title: String {
        switch self {
        case .needsLogin: L10n.text("health.needs_login")
        case .expired: L10n.text("health.expired")
        case .expiring: L10n.text("health.expiring")
        case .quotaCritical: L10n.text("health.quota_critical")
        case .quotaLow: L10n.text("health.quota_low")
        case .healthy: L10n.text("health.healthy")
        }
    }

    var compactTitle: String {
        switch self {
        case .needsLogin: L10n.text("health.needs_login.compact")
        case .expired: L10n.text("health.expired.compact")
        case .expiring: L10n.text("health.expiring.compact")
        case .quotaCritical: "Quota <10%"
        case .quotaLow: L10n.text("health.quota_low.compact")
        case .healthy: L10n.text("health.healthy.compact")
        }
    }

    var systemImage: String {
        switch self {
        case .needsLogin: "person.crop.circle.badge.exclamationmark"
        case .expired: "xmark.circle.fill"
        case .expiring: "calendar.badge.exclamationmark"
        case .quotaCritical: "gauge.with.dots.needle.0percent"
        case .quotaLow: "gauge.with.dots.needle.33percent"
        case .healthy: "checkmark.circle.fill"
        }
    }

    var needsAttention: Bool { self != .healthy }
}

struct TiboResetStatus: Decodable, Hashable {
    struct Post: Decodable, Hashable {
        let text: String
        let id: String
        let createdAt: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case text, id, url
            case createdAt = "created_at"
        }
    }

    let status: String
    let kind: String?
    let message: String
    let latestAt: String?
    let pendingAt: String?
    let fetchedAt: Int
    let source: String
    let xSource: String?
    let latestPost: Post?
    let hintPost: Post?
    let probabilityToday: Int?
    let probabilityBasis: String?
    let stale: Bool

    enum CodingKeys: String, CodingKey {
        case status, kind, message, source, stale
        case xSource = "x_source"
        case latestPost = "latest_post"
        case hintPost = "hint_post"
        case probabilityToday = "probability_today"
        case probabilityBasis = "probability_basis"
        case latestAt = "latest_at"
        case pendingAt = "pending_at"
        case fetchedAt = "fetched_at"
    }
}

struct AccountSnapshot: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let displayName: String?
    let email: String?
    let plan: String?
    let subscriptionExpiresAt: Int?
    let ok: Bool
    let error: String?
    let windows: [QuotaWindow]
    let resetCredits: Int
    let checkedAt: Int

    var identity: String { email ?? displayName ?? name }

    var isLocalDirect: Bool { id.hasPrefix("local:") }

    var subscriptionExpirationDate: Date? {
        guard let subscriptionExpiresAt, subscriptionExpiresAt > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(subscriptionExpiresAt))
    }

    func subscriptionRemainingText(at now: Date = .now, compact: Bool = false) -> String? {
        guard let expiration = subscriptionExpirationDate else { return nil }
        let remaining = expiration.timeIntervalSince(now)
        guard remaining > 0 else {
            return L10n.text(compact ? "subscription.expired.compact" : "subscription.expired")
        }
        if remaining >= 86_400 {
            let days = Int(ceil(remaining / 86_400))
            return L10n.format(compact ? "subscription.days.compact" : "subscription.days", days)
        }
        if remaining >= 3_600 {
            let hours = Int(ceil(remaining / 3_600))
            return L10n.format(compact ? "subscription.hours.compact" : "subscription.hours", hours)
        }
        return L10n.text(compact ? "subscription.less_hour.compact" : "subscription.less_hour")
    }

    func subscriptionIsExpired(at now: Date = .now) -> Bool {
        guard let expiration = subscriptionExpirationDate else { return false }
        return expiration <= now
    }

    func health(at now: Date = .now) -> AccountHealth {
        if isLocalDirect { return ok ? .healthy : .needsLogin }
        guard ok, !windows.isEmpty else { return .needsLogin }
        if subscriptionIsExpired(at: now) { return .expired }
        if let expiration = subscriptionExpirationDate,
           expiration.timeIntervalSince(now) <= 3 * 86_400 {
            return .expiring
        }
        let minimumRemaining = windows.map(\.remainingPercent).min() ?? 100
        if minimumRemaining <= 10 { return .quotaCritical }
        if minimumRemaining <= 20 { return .quotaLow }
        return .healthy
    }

    enum CodingKeys: String, CodingKey {
        case id, name, email, plan, ok, error, windows
        case displayName = "display_name"
        case subscriptionExpiresAt = "subscription_expires_at"
        case resetCredits = "reset_credits"
        case checkedAt = "checked_at"
    }
}

struct AppCapabilities: Decodable, Hashable {
    let reauthorize: Bool
    let refreshUsage: Bool
    let resetCredit: Bool
    let dynamicProfiles: Bool
    let manageAccounts: Bool?

    enum CodingKeys: String, CodingKey {
        case reauthorize
        case refreshUsage = "refresh_usage"
        case resetCredit = "reset_credit"
        case dynamicProfiles = "dynamic_profiles"
        case manageAccounts = "manage_accounts"
    }
}

struct NativeStatusResponse: Decodable {
    let generatedAt: Int
    let updatedAt: Int
    let pollSeconds: Int
    let capabilities: AppCapabilities
    let tiboReset: TiboResetStatus?
    let accounts: [AccountSnapshot]

    enum CodingKeys: String, CodingKey {
        case accounts, capabilities
        case tiboReset = "tibo_reset"
        case generatedAt = "generated_at"
        case updatedAt = "updated_at"
        case pollSeconds = "poll_seconds"
    }
}

struct LoginSession: Decodable, Hashable {
    let sessionID: String
    let accountID: String
    let status: String
    let verificationURL: String?
    let userCode: String?
    let expiresAt: Int
    let error: String?
    let account: AccountSnapshot?

    enum CodingKeys: String, CodingKey {
        case status, error, account
        case sessionID = "session_id"
        case accountID = "account_id"
        case verificationURL = "verification_url"
        case userCode = "user_code"
        case expiresAt = "expires_at"
    }
}

enum BrowserMode: String, Hashable {
    case web
    case device
    case directOAuth
    case cockpitOAuth
}

struct BrowserLaunch: Hashable {
    let mode: BrowserMode
    let code: String?
    let verificationURL: String?
    let directOAuthAttempt: DirectOAuthAttempt?
    let cockpitOAuthAttempt: CockpitOAuthAttempt?

    init(mode: BrowserMode, code: String?, verificationURL: String?) {
        self.mode = mode
        self.code = code
        self.verificationURL = verificationURL
        directOAuthAttempt = nil
        cockpitOAuthAttempt = nil
    }

    private init(directOAuthAttempt: DirectOAuthAttempt) {
        mode = .directOAuth
        code = nil
        verificationURL = nil
        self.directOAuthAttempt = directOAuthAttempt
        cockpitOAuthAttempt = nil
    }

    private init(cockpitOAuthAttempt: CockpitOAuthAttempt) {
        mode = .cockpitOAuth
        code = nil
        verificationURL = nil
        directOAuthAttempt = nil
        self.cockpitOAuthAttempt = cockpitOAuthAttempt
    }

    static let web = BrowserLaunch(mode: .web, code: nil, verificationURL: nil)

    static func directOAuth(_ attempt: DirectOAuthAttempt) -> BrowserLaunch {
        BrowserLaunch(directOAuthAttempt: attempt)
    }

    static func cockpitOAuth(_ attempt: CockpitOAuthAttempt) -> BrowserLaunch {
        BrowserLaunch(cockpitOAuthAttempt: attempt)
    }
}

enum AppRoute: Hashable {
    case accountDetail(String)
    case browser(String, BrowserLaunch)
}

enum AppTab: Hashable {
    case cockpit
    case profiles
    case mail
    case settings
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .cockpit
    @Published var cockpitPath = NavigationPath()
    @Published var profilePath = NavigationPath()
    @Published var mailPath = NavigationPath()

    func showAccount(_ accountID: String) {
        cockpitPath.append(AppRoute.accountDetail(accountID))
    }

    func openBrowser(accountID: String, launch: BrowserLaunch = .web) {
        if selectedTab == .profiles {
            profilePath.append(AppRoute.browser(accountID, launch))
        } else {
            cockpitPath.append(AppRoute.browser(accountID, launch))
        }
    }

    func openMailbox(_ mailboxID: UUID) {
        selectedTab = .mail
        mailPath.append(mailboxID)
    }
}

@MainActor
final class ProfileMappingStore: ObservableObject {
    @Published private(set) var mappings: [String: String]
    @Published private(set) var profiles: [WebProfile]
    @Published private(set) var webIdentities: [String: WebAccountIdentity]

    private let mappingKey = "CodexCockpit.profileMappings.v1"
    private let countKey = "CodexCockpit.profileCount.v1"
    private let identityKey = "CodexCockpit.webIdentities.v1"
    private let profileIDsKey = "CodexCockpit.profileIDs.v2"
    private let profileSequenceKey = "CodexCockpit.profileSequence.v2"
    private let defaults: UserDefaults
    private var nextProfileNumber: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mappings = defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        if let data = defaults.data(forKey: identityKey),
           let decoded = try? JSONDecoder().decode([String: WebAccountIdentity].self, from: data) {
            webIdentities = decoded
        } else {
            webIdentities = [:]
        }
        let initialProfiles: [WebProfile]
        if let ids = defaults.stringArray(forKey: profileIDsKey), !ids.isEmpty {
            initialProfiles = ids.map(WebProfile.init(id:))
        } else {
            let count = max(5, defaults.integer(forKey: countKey))
            initialProfiles = (1...count).map { WebProfile(id: String($0)) }
        }
        profiles = initialProfiles
        nextProfileNumber = max(
            defaults.integer(forKey: profileSequenceKey),
            initialProfiles.compactMap { Int($0.id) }.max() ?? 0
        )
    }

    func synchronize(accounts: [AccountSnapshot]) {
        while profiles.count < accounts.count { addProfile(save: false) }
        var used = Set(mappings.values)
        for account in accounts where mappings[account.id] == nil {
            let preferred = profiles.first(where: { $0.id == account.id && !used.contains($0.id) })
            let available = preferred ?? profiles.first(where: { !used.contains($0.id) })
            if let available {
                mappings[account.id] = available.id
                used.insert(available.id)
            }
        }
        for (profileID, identity) in webIdentities {
            if let accountID = uniqueAccountID(matching: identity, accounts: accounts) {
                assignMapping(accountID: accountID, to: profileID)
            }
        }
        save()
    }

    func profile(for accountID: String) -> WebProfile {
        let profileID = mappings[accountID] ?? accountID
        return profile(id: profileID)
    }

    func profile(id profileID: String) -> WebProfile {
        profiles.first(where: { $0.id == profileID }) ?? WebProfile(id: profileID)
    }

    func mappedAccountID(for profileID: String) -> String? {
        mappings.first(where: { $0.value == profileID })?.key
    }

    func assign(accountID: String, to profileID: String) {
        assignMapping(accountID: accountID, to: profileID)
        save()
    }

    func record(identity: WebAccountIdentity, for profileID: String, accounts: [AccountSnapshot]) {
        webIdentities[profileID] = identity
        if let accountID = uniqueAccountID(matching: identity, accounts: accounts) {
            assignMapping(accountID: accountID, to: profileID)
        }
        save()
    }

    func displayIdentity(for account: AccountSnapshot) -> String {
        let profileID = mappings[account.id] ?? account.id
        if let identity = webIdentities[profileID] {
            return identity.label
        }
        return Self.nonEmpty(account.email)
            ?? Self.nonEmpty(account.displayName)
            ?? account.name
    }

    func clearIdentity(for profileID: String) {
        webIdentities.removeValue(forKey: profileID)
        save()
    }

    @discardableResult
    func createDedicatedProfile(for accountID: String) -> WebProfile {
        if let profileID = mappings[accountID] { return profile(id: profileID) }
        let used = Set(mappings.values)
        let profile: WebProfile
        if let available = profiles.first(where: { !used.contains($0.id) }) {
            profile = available
        } else {
            profile = nextProfile()
            profiles.append(profile)
        }
        mappings[accountID] = profile.id
        save()
        return profile
    }

    @discardableResult
    func removeAccount(_ accountID: String) -> WebProfile? {
        guard let profileID = mappings.removeValue(forKey: accountID) else { return nil }
        let removed = profile(id: profileID)
        webIdentities.removeValue(forKey: profileID)
        profiles.removeAll { $0.id == profileID }
        save()
        return removed
    }

    private func assignMapping(accountID: String, to profileID: String) {
        let oldProfile = mappings[accountID]
        if let other = mappings.first(where: { $0.key != accountID && $0.value == profileID })?.key {
            if let oldProfile { mappings[other] = oldProfile } else { mappings.removeValue(forKey: other) }
        }
        mappings[accountID] = profileID
    }

    private func uniqueAccountID(
        matching identity: WebAccountIdentity,
        accounts: [AccountSnapshot]
    ) -> String? {
        guard let email = identity.normalizedEmail else { return nil }
        let matches = accounts.filter { $0.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email }
        return matches.count == 1 ? matches[0].id : nil
    }

    func addProfile(save shouldSave: Bool = true) {
        profiles.append(nextProfile())
        if shouldSave { save() }
    }

    private func nextProfile() -> WebProfile {
        nextProfileNumber += 1
        return WebProfile(id: String(nextProfileNumber))
    }

    private func save() {
        defaults.set(mappings, forKey: mappingKey)
        defaults.set(profiles.count, forKey: countKey)
        defaults.set(profiles.map(\.id), forKey: profileIDsKey)
        defaults.set(nextProfileNumber, forKey: profileSequenceKey)
        if let data = try? JSONEncoder().encode(webIdentities) {
            defaults.set(data, forKey: identityKey)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AppURLs {
    static let base = URL(string: "https://mach-dns.tail2e377d.ts.net/codex/")!
    static let chatGPT = URL(string: "https://chatgpt.com/")!
    static let chatGPTSession = URL(string: "https://chatgpt.com/api/auth/session")!
    static let deviceLogin = URL(string: "https://auth.openai.com/codex/device")!

    static func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: base)!.absoluteURL
    }
}
