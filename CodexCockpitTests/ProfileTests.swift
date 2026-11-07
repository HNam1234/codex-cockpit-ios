import XCTest
@testable import CodexCockpit

final class ProfileTests: XCTestCase {
    func testOriginalFiveProfilesKeepTheirPersistentStores() {
        XCTAssertEqual(WebProfile.persistentIdentifier(for: "1"), UUID(uuidString: "C0D3C001-0000-4000-8000-000000000001"))
        XCTAssertEqual(WebProfile.persistentIdentifier(for: "5"), UUID(uuidString: "C0D3C005-0000-4000-8000-000000000005"))
    }

    func testAdditionalProfilesGetStableUniqueStores() {
        let first = WebProfile.persistentIdentifier(for: "account-27")
        XCTAssertEqual(first, WebProfile.persistentIdentifier(for: "account-27"))
        XCTAssertNotEqual(first, WebProfile.persistentIdentifier(for: "account-28"))
    }

    func testNativeAPIUsesPrivateEndpoints() {
        XCTAssertEqual(AppURLs.endpoint("app-status").host, "mach-dns.tail2e377d.ts.net")
        XCTAssertEqual(AppURLs.endpoint("app-status").path, "/codex/app-status")
        XCTAssertEqual(AppURLs.endpoint("app-auth/start").path, "/codex/app-auth/start")
        XCTAssertEqual(AppURLs.endpoint("app-reset-credit").path, "/codex/app-reset-credit")
    }

    func testDeviceLoginIsOfficialOpenAIHost() {
        XCTAssertEqual(AppURLs.deviceLogin.host, "auth.openai.com")
        XCTAssertEqual(AppURLs.deviceLogin.path, "/codex/device")
    }
}
