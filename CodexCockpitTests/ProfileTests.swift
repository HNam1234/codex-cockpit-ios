import XCTest
@testable import CodexCockpit

final class ProfileTests: XCTestCase {
    func testFiveProfilesHaveUniquePersistentStores() {
        XCTAssertEqual(AccountProfile.all.count, 5)
        XCTAssertEqual(Set(AccountProfile.all.map(\.dataStoreIdentifier)).count, 5)
        XCTAssertFalse(AccountProfile.all.map(\.dataStoreIdentifier).contains(AccountProfile.dashboardDataStoreIdentifier))
    }

    func testDashboardLoginLinkValidation() {
        XCTAssertTrue(AppURLs.isDashboardLoginLink(URL(string: "https://mach-dns.tail2e377d.ts.net/codex/login?t=abc")!))
        XCTAssertFalse(AppURLs.isDashboardLoginLink(URL(string: "https://evil.example/codex/login?t=abc")!))
        XCTAssertFalse(AppURLs.isDashboardLoginLink(URL(string: "http://mach-dns.tail2e377d.ts.net/codex/login?t=abc")!))
    }
}
