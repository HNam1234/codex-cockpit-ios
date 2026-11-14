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

    func testStatusPollingIntervalIsClampedToSafeActiveRange() {
        XCTAssertEqual(CockpitStore.clampedPollSeconds(0), 60)
        XCTAssertEqual(CockpitStore.clampedPollSeconds(30), 60)
        XCTAssertEqual(CockpitStore.clampedPollSeconds(900), 900)
        XCTAssertEqual(CockpitStore.clampedPollSeconds(7_200), 3_600)
    }

    func testTiboPresentationExposesStateFreshnessAndSource() {
        let post = TiboResetStatus.Post(
            text: "A reset hint",
            id: "post-1",
            createdAt: "2026-11-14T06:00:00Z",
            url: "https://x.com/thsottiaux/status/post-1"
        )
        let signal = TiboResetStatus(
            status: "likely",
            kind: "hint",
            message: "Likely today",
            latestAt: nil,
            pendingAt: nil,
            fetchedAt: 100,
            source: "OpenTheRank",
            xSource: "@thsottiaux",
            latestPost: nil,
            hintPost: post,
            probabilityToday: 80,
            probabilityBasis: "history+x",
            stale: false
        )

        XCTAssertEqual(signal.presentationStatus, L10n.text("tibo.status.likely"))
        XCTAssertEqual(signal.presentationIcon, "sparkles")
        XCTAssertEqual(signal.presentationURL, URL(string: post.url))
        XCTAssertEqual(signal.presentationSource, "@thsottiaux")
    }
}
