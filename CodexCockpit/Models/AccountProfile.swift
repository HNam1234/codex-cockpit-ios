import CryptoKit
import Foundation
import SwiftUI

struct AccountProfile: Identifiable, Hashable, Codable {
    let id: String
    let name: String

    var dataStoreIdentifier: UUID { Self.persistentIdentifier(for: id) }

    var tint: Color {
        let palette: [Color] = [.blue, .cyan, .green, .orange, .purple, .pink, .indigo, .mint]
        let total = id.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) }
        return palette[Int(total % UInt64(palette.count))]
    }

    static let dashboardDataStoreIdentifier = UUID(uuidString: "C0D3C000-0000-4000-8000-000000000000")!

    static let fallback: [AccountProfile] = (1...5).map {
        .init(id: String($0), name: "Codex \($0)")
    }

    static func persistentIdentifier(for id: String) -> UUID {
        // Preserve the original five stores so upgrades keep their existing cookies.
        if let number = Int(id), (1...5).contains(number) {
            return UUID(uuidString: String(format: "C0D3C%03d-0000-4000-8000-%012d", number, number))!
        }
        let digest = SHA256.hash(data: Data("CodexCockpit.Profile.\(id)".utf8))
        let hex = digest.prefix(16).map { String(format: "%02X", $0) }.joined()
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-8\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value)!
    }
}

enum ProfileAction: String, Hashable {
    case web
    case device
}

struct ProfileRoute: Hashable {
    let id: String
    let action: ProfileAction
}

enum AppTab: Hashable {
    case cockpit
    case accounts
    case settings
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .cockpit
    @Published var accountPath = NavigationPath()

    func open(_ route: ProfileRoute) {
        accountPath = NavigationPath()
        accountPath.append(route)
        selectedTab = .accounts
    }
}

@MainActor
final class AccountDirectory: ObservableObject {
    @Published private(set) var profiles: [AccountProfile]
    private let cacheKey = "CodexCockpit.accountProfiles.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([AccountProfile].self, from: data),
           !cached.isEmpty {
            profiles = cached
        } else {
            profiles = AccountProfile.fallback
        }
    }

    func profile(id: String) -> AccountProfile {
        profiles.first(where: { $0.id == id }) ?? .init(id: id, name: "Codex \(id)")
    }

    func refresh() async {
        guard !AppAuth.cockpitToken.isEmpty else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: AppURLs.accountConfigRequest)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(AccountConfigResponse.self, from: data)
            var seen = Set<String>()
            let unique = decoded.accounts.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
            guard !unique.isEmpty else { return }
            profiles = unique
            if let cached = try? JSONEncoder().encode(unique) {
                UserDefaults.standard.set(cached, forKey: cacheKey)
            }
        } catch {
            // Keep the last known profile list when the VPS is temporarily unavailable.
        }
    }
}

private struct AccountConfigResponse: Decodable {
    let accounts: [AccountProfile]
}

enum AppURLs {
    static let dashboard = URL(string: "https://mach-dns.tail2e377d.ts.net/codex/")!
    static let dashboardAppLogin = URL(string: "https://mach-dns.tail2e377d.ts.net/codex/app-login")!
    static let accountConfig = URL(string: "https://mach-dns.tail2e377d.ts.net/codex/app-config")!
    static let chatGPT = URL(string: "https://chatgpt.com/")!
    static let deviceLogin = URL(string: "https://auth.openai.com/codex/device")!

    static var dashboardRequest: URLRequest { tokenRequest(url: dashboardAppLogin) }
    static var accountConfigRequest: URLRequest { tokenRequest(url: accountConfig) }

    static func profileRoute(from url: URL) -> ProfileRoute? {
        guard url.host == dashboard.host,
              url.path == "/codex/app/profile",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty,
              let actionValue = components.queryItems?.first(where: { $0.name == "action" })?.value,
              let action = ProfileAction(rawValue: actionValue) else { return nil }
        return ProfileRoute(id: id, action: action)
    }

    private static func tokenRequest(url: URL) -> URLRequest {
        guard !AppAuth.cockpitToken.isEmpty else { return URLRequest(url: url) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = AppAuth.cockpitToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = "k=\(encoded)".data(using: .utf8)
        return request
    }
}
