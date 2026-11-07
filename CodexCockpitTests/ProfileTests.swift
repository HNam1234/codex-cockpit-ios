import XCTest
@testable import CodexCockpit

final class ProfileTests: XCTestCase {
    func testOriginalFiveProfilesKeepTheirPersistentStores() {
        XCTAssertEqual(AccountProfile.persistentIdentifier(for: "1"), UUID(uuidString: "C0D3C001-0000-4000-8000-000000000001"))
        XCTAssertEqual(AccountProfile.persistentIdentifier(for: "5"), UUID(uuidString: "C0D3C005-0000-4000-8000-000000000005"))
        XCTAssertFalse(AccountProfile.fallback.map(\.dataStoreIdentifier).contains(AccountProfile.dashboardDataStoreIdentifier))
    }

    func testAdditionalProfilesGetStableUniqueStores() {
        let first = AccountProfile.persistentIdentifier(for: "account-27")
        XCTAssertEqual(first, AccountProfile.persistentIdentifier(for: "account-27"))
        XCTAssertNotEqual(first, AccountProfile.persistentIdentifier(for: "account-28"))
    }

    func testDashboardUsesPrivatePostBootstrap() {
        XCTAssertEqual(AppURLs.dashboardRequest.url?.host, "mach-dns.tail2e377d.ts.net")
        XCTAssertEqual(AppURLs.dashboardRequest.url?.path, "/codex/app-login")
        XCTAssertEqual(AppURLs.dashboardRequest.httpMethod, "POST")
        XCTAssertNil(AppURLs.dashboardRequest.url?.query)
    }

    func testAccountConfigIsPrivatePostAndRouteMapsToProfile() {
        XCTAssertEqual(AppURLs.accountConfigRequest.url?.path, "/codex/app-config")
        XCTAssertEqual(AppURLs.accountConfigRequest.httpMethod, "POST")
        let url = URL(string: "https://mach-dns.tail2e377d.ts.net/codex/app/profile?id=12&action=device")!
        XCTAssertEqual(AppURLs.profileRoute(from: url), ProfileRoute(id: "12", action: .device))
    }
}
