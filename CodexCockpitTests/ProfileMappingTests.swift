import XCTest
@testable import CodexCockpit

@MainActor
final class ProfileMappingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ProfileMappingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testWebIdentityTrimsValuesAndRejectsBlankPayload() {
        let identity = WebAccountIdentity(name: "  Nam Nguyen  ", email: "  USER@Example.com ")

        XCTAssertEqual(identity?.name, "Nam Nguyen")
        XCTAssertEqual(identity?.email, "USER@Example.com")
        XCTAssertNil(WebAccountIdentity(name: " \n ", email: "\t"))
    }

    func testJavaScriptIdentityPayloadParsesOnlyStringNameAndEmail() {
        let identity = WebAccountIdentity(javaScriptValue: [
            "name": "  Alice  ",
            "email": " alice@example.com "
        ])

        XCTAssertEqual(identity?.name, "Alice")
        XCTAssertEqual(identity?.email, "alice@example.com")
        XCTAssertNil(WebAccountIdentity(javaScriptValue: "alice@example.com"))
        XCTAssertNil(WebAccountIdentity(javaScriptValue: ["name": 42, "email": false]))
        XCTAssertNil(WebAccountIdentity(javaScriptValue: ["name": " ", "email": "\n"]))
    }

    func testUniqueCaseInsensitiveEmailMatchSwapsExistingMappings() {
        let store = ProfileMappingStore(defaults: defaults)
        let first = account(id: "1", name: "Codex 1", email: "first@example.com")
        let second = account(id: "2", name: "Codex 2", email: "SECOND@example.com")
        store.synchronize(accounts: [first, second])

        store.record(
            identity: WebAccountIdentity(name: "Second", email: " second@EXAMPLE.com ")!,
            for: "1",
            accounts: [first, second]
        )

        XCTAssertEqual(store.mappedAccountID(for: "1"), "2")
        XCTAssertEqual(store.mappedAccountID(for: "2"), "1")
    }

    func testAmbiguousEmailDoesNotChangeMappings() {
        let store = ProfileMappingStore(defaults: defaults)
        let first = account(id: "1", name: "Codex 1", email: "same@example.com")
        let second = account(id: "2", name: "Codex 2", email: "SAME@example.com")
        store.synchronize(accounts: [first, second])

        store.record(
            identity: WebAccountIdentity(name: "Shared", email: "same@example.com")!,
            for: "2",
            accounts: [first, second]
        )

        XCTAssertEqual(store.mappedAccountID(for: "1"), "1")
        XCTAssertEqual(store.mappedAccountID(for: "2"), "2")
    }

    func testMappedWebIdentityIsPreferredWhenQuotaIdentityIsUnavailable() {
        let store = ProfileMappingStore(defaults: defaults)
        let unavailable = account(id: "1", name: "Codex 1")
        store.synchronize(accounts: [unavailable])
        store.record(
            identity: WebAccountIdentity(name: "Web Account", email: "web@example.com")!,
            for: "1",
            accounts: [unavailable]
        )

        XCTAssertEqual(store.displayIdentity(for: unavailable), "Web Account")
    }

    func testWebIdentityPersistsPerProfile() {
        let account = account(id: "1", name: "Codex 1")
        var store: ProfileMappingStore? = ProfileMappingStore(defaults: defaults)
        store?.synchronize(accounts: [account])
        store?.record(
            identity: WebAccountIdentity(name: nil, email: "saved@example.com")!,
            for: "1",
            accounts: [account]
        )
        store = nil

        let restored = ProfileMappingStore(defaults: defaults)
        XCTAssertEqual(restored.displayIdentity(for: account), "saved@example.com")
    }

    func testClearingProfileIdentityRestoresAccountFallback() {
        let store = ProfileMappingStore(defaults: defaults)
        let account = account(id: "1", name: "Codex 1")
        store.synchronize(accounts: [account])
        store.record(
            identity: WebAccountIdentity(name: "Temporary", email: nil)!,
            for: "1",
            accounts: [account]
        )

        store.clearIdentity(for: "1")

        XCTAssertEqual(store.displayIdentity(for: account), "Codex 1")
    }

    func testBrowserBindingKeepsOriginalProfileAfterAutomaticRemap() {
        let store = ProfileMappingStore(defaults: defaults)
        let first = account(id: "1", name: "Codex 1", email: "first@example.com")
        let second = account(id: "2", name: "Codex 2", email: "second@example.com")
        store.synchronize(accounts: [first, second])
        let binding = BrowserProfileBinding(accountID: first.id, mappings: store)

        store.assign(accountID: first.id, to: "2")

        XCTAssertEqual(binding.profile(in: store).id, "1")
    }

    func testDedicatedProfileIsUniqueAndRemovedWithAccount() {
        let store = ProfileMappingStore(defaults: defaults)

        let created = store.createDedicatedProfile(for: "new-account")

        XCTAssertEqual(store.profile(for: "new-account"), created)
        XCTAssertEqual(store.mappedAccountID(for: created.id), "new-account")
        XCTAssertEqual(store.removeAccount("new-account"), created)
        XCTAssertNil(store.mappedAccountID(for: created.id))
        XCTAssertFalse(store.profiles.contains(created))

        let replacement = store.createDedicatedProfile(for: "replacement")
        XCTAssertNotEqual(replacement.id, created.id)
    }

    private func account(
        id: String,
        name: String,
        displayName: String? = nil,
        email: String? = nil
    ) -> AccountSnapshot {
        AccountSnapshot(
            id: id,
            name: name,
            displayName: displayName,
            email: email,
            plan: nil,
            subscriptionExpiresAt: nil,
            ok: email != nil,
            error: email == nil ? "Unavailable" : nil,
            windows: [],
            resetCredits: 0,
            checkedAt: 0
        )
    }
}
