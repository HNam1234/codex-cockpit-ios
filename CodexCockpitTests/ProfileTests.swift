import XCTest
@testable import CodexCockpit

final class ProfileTests: XCTestCase {
    func testFiveProfilesHaveUniquePersistentStores() {
        XCTAssertEqual(AccountProfile.all.count, 5)
        XCTAssertEqual(Set(AccountProfile.all.map(\.dataStoreIdentifier)).count, 5)
        XCTAssertFalse(AccountProfile.all.map(\.dataStoreIdentifier).contains(AccountProfile.dashboardDataStoreIdentifier))
    }

    func testDashboardUsesPrivatePostBootstrap() {
        XCTAssertEqual(AppURLs.dashboardRequest.url?.host, "mach-dns.tail2e377d.ts.net")
        XCTAssertEqual(AppURLs.dashboardRequest.url?.path, "/codex/app-login")
        XCTAssertEqual(AppURLs.dashboardRequest.httpMethod, "POST")
        XCTAssertNil(AppURLs.dashboardRequest.url?.query)
    }
}
