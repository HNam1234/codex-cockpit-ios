import XCTest
@testable import CodexCockpit

final class CockpitCredentialTests: XCTestCase {
    func testTokenValidationTrimsAValidURLSafeToken() throws {
        let raw = "  abcdefghijklmnopqrstuvwxyz_1234567890-ABCD  "

        let token = try CockpitCredential.validate(raw)

        XCTAssertEqual(token, "abcdefghijklmnopqrstuvwxyz_1234567890-ABCD")
    }

    func testTokenValidationRejectsShortOrUnsafeValues() {
        XCTAssertThrowsError(try CockpitCredential.validate("short"))
        XCTAssertThrowsError(try CockpitCredential.validate(String(repeating: "a", count: 31) + "!"))
        XCTAssertThrowsError(try CockpitCredential.validate(String(repeating: "a", count: 32) + "é"))
        XCTAssertThrowsError(try CockpitCredential.validate(""))
    }

    func testKeychainStoreRoundTripsAndClearsToken() throws {
        let store = CockpitCredentialStore(
            service: "CockpitCredentialTests.\(UUID().uuidString)",
            account: "test-token"
        )
        defer { try? store.clear() }
        let token = String(repeating: "a", count: 40)

        XCTAssertNil(try store.load())
        try store.save(token)
        XCTAssertEqual(try store.load(), token)
        XCTAssertTrue(store.isConfigured)

        try store.clear()
        XCTAssertNil(try store.load())
        XCTAssertFalse(store.isConfigured)
    }
}
