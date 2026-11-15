import XCTest
@testable import CodexCockpit

final class MailTMClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MailTMURLProtocolStub.reset()
    }

    override func tearDown() {
        MailTMURLProtocolStub.reset()
        super.tearDown()
    }

    func testCreatesAccountAndAuthenticatesUsingExactMailTMRequests() async throws {
        let recorder = MailTMRequestRecorder()
        MailTMURLProtocolStub.handler = { request in
            recorder.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/domains"):
                return Self.response(request, status: 200, json: Self.domainsJSON)
            case ("POST", "/accounts"):
                return Self.response(request, status: 201, json: Self.accountJSON)
            case ("POST", "/token"):
                return Self.response(request, status: 200, json: #"{"id":"account-id","token":"secret-token"}"#)
            default:
                return Self.response(request, status: 404, json: "{}")
            }
        }
        let client = makeClient(seed: { domain in
            MailTMAccountSeed(address: "random@\(domain)", password: "secret-password")
        })

        let domains = try await client.availableDomains()
        let seed = try await client.makeAccountSeed(domain: domains[0].domain)
        let account = try await client.createAccount(address: seed.address, password: seed.password)
        let credential = try await client.authenticate(address: seed.address, password: seed.password)

        XCTAssertEqual(domains.map(\.domain), ["example.test"])
        XCTAssertEqual(account.id, "account-id")
        XCTAssertEqual(credential, MailTMCredential(
            providerAccountID: "account-id",
            address: "random@example.test",
            password: "secret-password",
            token: "secret-token"
        ))
        let requests = recorder.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/domains", "/accounts", "/token"])
        XCTAssertEqual(requests[0].url?.query, "page=1")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try Self.jsonBody(requests[1]), [
            "address": "random@example.test",
            "password": "secret-password"
        ])
        XCTAssertEqual(try Self.jsonBody(requests[2]), [
            "address": "random@example.test",
            "password": "secret-password"
        ])
    }

    func testListsReadsMarksSeenAndDeletesWithBearerTokenAndEncodedIDs() async throws {
        let recorder = MailTMRequestRecorder()
        MailTMURLProtocolStub.handler = { request in
            recorder.append(request)
            let path = request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
            } ?? ""
            switch (request.httpMethod, path) {
            case ("GET", "/messages"):
                return Self.response(request, status: 200, json: Self.messageListJSON)
            case ("GET", "/messages/id%2Fwith%20space"):
                return Self.response(request, status: 200, json: Self.messageDetailJSON)
            case ("PATCH", "/messages/id%2Fwith%20space"):
                return Self.response(request, status: 200, json: Self.messageDetailJSON)
            case ("DELETE", "/accounts/account-id"):
                return Self.response(request, status: 204, json: "")
            default:
                return Self.response(request, status: 404, json: "{}")
            }
        }
        let client = makeClient()
        let mailboxID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        let summaries = try await client.listMessages(mailboxID: mailboxID, token: "secret-token")
        let detail = try await client.message(
            mailboxID: mailboxID,
            messageID: "id/with space",
            token: "secret-token"
        )
        try await client.markSeen(messageID: "id/with space", token: "secret-token")
        try await client.deleteAccount(accountID: "account-id", token: "secret-token")

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].subject, "Verify your account")
        XCTAssertEqual(summaries[0].text, "")
        XCTAssertEqual(detail.text, "Your verification code is 482731")
        XCTAssertEqual(detail.senderAddress, "noreply@example.com")
        XCTAssertEqual(detail.attachments, [DisposableAttachment(
            id: "attachment-id",
            fileName: "notice.txt",
            mediaType: "text/plain",
            size: 42
        )])
        let requests = recorder.requests
        XCTAssertTrue(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token"
        })
        XCTAssertEqual(try Self.jsonBody(requests[2]), ["seen": true])
        XCTAssertNil(requests[3].httpBody)
    }

    func testRejectsUnexpectedHostAndCrossHostRedirectWithoutLeakingSecrets() async {
        let client = makeClient(baseURL: URL(string: "https://api.mail.tm.evil/secret-token")!)

        do {
            _ = try await client.availableDomains()
            XCTFail("Expected rejected host")
        } catch {
            XCTAssertEqual(error as? DisposableMailServiceError, .rejectedHost)
            XCTAssertFalse(String(describing: error).contains("secret-token"))
            XCTAssertFalse(error.localizedDescription.contains("secret-password"))
        }
        XCTAssertTrue(MailTMRedirectGuard.isAllowed(URL(string: "https://api.mail.tm/messages")!))
        XCTAssertFalse(MailTMRedirectGuard.isAllowed(URL(string: "https://api.mail.tm.evil/messages")!))
        XCTAssertFalse(MailTMRedirectGuard.isAllowed(URL(string: "http://api.mail.tm/messages")!))
    }

    func testMapsAccountConflictWithoutRetryingNonIdempotentCreate() async {
        let counter = MailTMCounter()
        MailTMURLProtocolStub.handler = { request in
            _ = counter.increment()
            return Self.response(request, status: 422, json: #"{"detail":"already used"}"#)
        }
        let client = makeClient()

        do {
            _ = try await client.createAccount(
                address: "candidate@example.test",
                password: "secret-password"
            )
            XCTFail("Expected conflict")
        } catch {
            XCTAssertEqual(error as? DisposableMailServiceError, .conflict)
        }
        XCTAssertEqual(counter.value, 1)
    }

    func testSerializesRequestsToFourPerSecond() async throws {
        let delays = MailTMDelayRecorder()
        MailTMURLProtocolStub.handler = { request in
            Self.response(request, status: 200, json: Self.domainsJSON)
        }
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let client = makeClient(
            minimumRequestInterval: 0.25,
            now: { fixedNow },
            sleep: { delay in await delays.append(delay) }
        )

        _ = try await client.availableDomains()
        _ = try await client.availableDomains()

        assertTimeIntervalsEqual(await delays.values, [0.25], accuracy: 0.001)
    }

    func testHonorsRetryAfterForRateLimitedRead() async throws {
        let attempts = MailTMCounter()
        let delays = MailTMDelayRecorder()
        MailTMURLProtocolStub.handler = { request in
            let attempt = attempts.increment()
            if attempt == 1 {
                return Self.response(
                    request,
                    status: 429,
                    headers: ["Retry-After": "2"],
                    json: "{}"
                )
            }
            return Self.response(request, status: 200, json: Self.domainsJSON)
        }
        let client = makeClient(sleep: { delay in await delays.append(delay) })

        let domains = try await client.availableDomains()

        XCTAssertEqual(domains.count, 1)
        XCTAssertEqual(attempts.value, 2)
        assertTimeIntervalsEqual(await delays.values, [2], accuracy: 0.001)
    }

    func testRetriesTransientServerReadsWithBoundedExponentialBackoff() async throws {
        let attempts = MailTMCounter()
        let delays = MailTMDelayRecorder()
        MailTMURLProtocolStub.handler = { request in
            let attempt = attempts.increment()
            guard attempt >= 3 else {
                return Self.response(request, status: 503, json: "{}")
            }
            return Self.response(request, status: 200, json: Self.domainsJSON)
        }
        let client = makeClient(
            sleep: { delay in await delays.append(delay) },
            jitter: { _ in 0 }
        )

        _ = try await client.availableDomains()

        XCTAssertEqual(attempts.value, 3)
        assertTimeIntervalsEqual(await delays.values, [1, 2], accuracy: 0.001)
    }

    private func makeClient(
        baseURL: URL = URL(string: "https://api.mail.tm")!,
        minimumRequestInterval: TimeInterval = 0,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in },
        jitter: @escaping @Sendable (TimeInterval) -> TimeInterval = { $0 },
        seed: @escaping @Sendable (String) throws -> MailTMAccountSeed = { domain in
            MailTMAccountSeed(address: "generated@\(domain)", password: "generated-password")
        }
    ) -> MailTMClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MailTMURLProtocolStub.self]
        return MailTMClient(
            session: URLSession(configuration: configuration),
            baseURL: baseURL,
            minimumRequestInterval: minimumRequestInterval,
            now: now,
            sleep: sleep,
            jitter: jitter,
            accountSeed: seed
        )
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        headers: [String: String] = [:],
        json: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (response, Data(json.utf8))
    }

    private static func jsonBody(_ request: URLRequest) throws -> [String: AnyHashable] {
        let data = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: AnyHashable])
        return object
    }

    private static let domainsJSON = #"{"hydra:member":[{"id":"domain-id","domain":"example.test","isActive":true,"isPrivate":false,"createdAt":"2026-11-15T00:00:00+00:00","updatedAt":"2026-11-15T00:00:00+00:00"}],"hydra:totalItems":1}"#

    private static let accountJSON = #"{"id":"account-id","address":"random@example.test","quota":40000000,"used":0,"isDisabled":false,"isDeleted":false,"createdAt":"2026-11-15T00:00:00+00:00","updatedAt":"2026-11-15T00:00:00+00:00"}"#

    private static let messageListJSON = #"{"hydra:member":[{"id":"id/with space","accountId":"account-id","msgid":"msg-id","from":{"address":"noreply@example.com","name":"OpenAI"},"to":[{"address":"random@example.test","name":""}],"subject":"Verify your account","intro":"Your verification code","seen":false,"isDeleted":false,"hasAttachments":true,"size":123,"downloadUrl":"/messages/id/download","createdAt":"2026-11-15T00:00:00+00:00","updatedAt":"2026-11-15T00:00:00+00:00"}],"hydra:totalItems":1}"#

    private static let messageDetailJSON = #"{"id":"id/with space","accountId":"account-id","msgid":"msg-id","from":{"address":"noreply@example.com","name":"OpenAI"},"to":[{"address":"random@example.test","name":""}],"subject":"Verify your account","intro":"Your verification code","seen":false,"isDeleted":false,"hasAttachments":true,"size":123,"downloadUrl":"/messages/id/download","text":"Your verification code is 482731","html":["<p>Your verification code is <b>482731</b></p>"],"attachments":[{"id":"attachment-id","filename":"notice.txt","contentType":"text/plain","disposition":"attachment","transferEncoding":"base64","related":false,"size":42,"downloadUrl":"/messages/id/attachment-id"}],"createdAt":"2026-11-15T00:00:00+00:00","updatedAt":"2026-11-15T00:00:00+00:00"}"#
}

private final class MailTMURLProtocolStub: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class MailTMRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storage }
    }

    func append(_ request: URLRequest) {
        var snapshot = request
        if snapshot.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }

            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            snapshot.httpBody = body
        }

        lock.withLock { storage.append(snapshot) }
    }
}

private final class MailTMCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int { lock.withLock { storage } }

    func increment() -> Int {
        lock.withLock {
            storage += 1
            return storage
        }
    }
}

private actor MailTMDelayRecorder {
    private var storage: [TimeInterval] = []
    var values: [TimeInterval] { storage }
    func append(_ value: TimeInterval) { storage.append(value) }
}

private extension XCTestCase {
    func assertTimeIntervalsEqual(
        _ actual: [TimeInterval],
        _ expected: [TimeInterval],
        accuracy: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let matches = actual.count == expected.count &&
            zip(actual, expected).allSatisfy { abs($0 - $1) <= accuracy }
        XCTAssertTrue(
            matches,
            "Expected \(actual) to equal \(expected) ±\(accuracy)",
            file: file,
            line: line
        )
    }
}
