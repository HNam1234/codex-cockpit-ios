import Foundation
import SwiftUI

struct AccountProfile: Identifiable, Hashable {
    let id: Int
    let name: String
    let dataStoreIdentifier: UUID
    let tint: Color

    static let dashboardDataStoreIdentifier = UUID(uuidString: "C0D3C000-0000-4000-8000-000000000000")!

    static let all: [AccountProfile] = [
        .init(id: 1, name: "Codex 1", dataStoreIdentifier: UUID(uuidString: "C0D3C001-0000-4000-8000-000000000001")!, tint: .blue),
        .init(id: 2, name: "Codex 2", dataStoreIdentifier: UUID(uuidString: "C0D3C002-0000-4000-8000-000000000002")!, tint: .cyan),
        .init(id: 3, name: "Codex 3", dataStoreIdentifier: UUID(uuidString: "C0D3C003-0000-4000-8000-000000000003")!, tint: .green),
        .init(id: 4, name: "Codex 4", dataStoreIdentifier: UUID(uuidString: "C0D3C004-0000-4000-8000-000000000004")!, tint: .orange),
        .init(id: 5, name: "Codex 5", dataStoreIdentifier: UUID(uuidString: "C0D3C005-0000-4000-8000-000000000005")!, tint: .purple)
    ]
}

enum AppURLs {
    static let dashboard = URL(string: "https://mach-dns.tail2e377d.ts.net/codex/")!
    static let chatGPT = URL(string: "https://chatgpt.com/")!
    static let deviceLogin = URL(string: "https://auth.openai.com/codex/device")!

    static func isDashboardLoginLink(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host == dashboard.host
            && url.path == "/codex/login"
            && url.query?.contains("t=") == true
    }
}
