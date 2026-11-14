import XCTest
@testable import CodexCockpit

final class TiboAlertTests: XCTestCase {
    func testLikelySignalBuildsActionableAlertFromHintPost() {
        let content = TiboAlertPolicy.content(for: signal(
            status: "likely",
            message: "Có thể reset hôm nay",
            hintPost: post(id: "post-123", text: "We shipped an update")
        ))

        XCTAssertEqual(content?.identifier, "tibo.likely.post-123")
        XCTAssertEqual(content?.title, L10n.text("tibo.notification.likely"))
        XCTAssertEqual(content?.body, "We shipped an update")
    }

    func testConfirmedSignalUsesConfirmedTitle() {
        let content = TiboAlertPolicy.content(for: signal(
            status: "yes",
            message: "Reset confirmed",
            latestPost: post(id: "post-confirmed", text: "Reset is live")
        ))

        XCTAssertEqual(content?.identifier, "tibo.yes.post-confirmed")
        XCTAssertEqual(content?.title, L10n.text("tibo.notification.confirmed"))
        XCTAssertEqual(content?.body, "Reset is live")
    }

    func testStaleNoAndUnknownSignalsDoNotAlert() {
        XCTAssertNil(TiboAlertPolicy.content(for: signal(status: "likely", stale: true)))
        XCTAssertNil(TiboAlertPolicy.content(for: signal(status: "no")))
        XCTAssertNil(TiboAlertPolicy.content(for: signal(status: "unknown")))
    }

    func testIdentifierIsStableAcrossTrackerRefreshes() {
        let first = TiboAlertPolicy.content(for: signal(
            status: "likely",
            fetchedAt: 100,
            hintPost: post(id: "same-post", text: "Signal")
        ))
        let second = TiboAlertPolicy.content(for: signal(
            status: "likely",
            fetchedAt: 200,
            hintPost: post(id: "same-post", text: "Signal")
        ))

        XCTAssertEqual(first?.identifier, second?.identifier)
    }

    func testEscalationFromLikelyToYesGetsANewIdentifier() {
        let likely = TiboAlertPolicy.content(for: signal(
            status: "likely",
            hintPost: post(id: "same-post", text: "Signal")
        ))
        let confirmed = TiboAlertPolicy.content(for: signal(
            status: "yes",
            hintPost: post(id: "same-post", text: "Signal")
        ))

        XCTAssertNotEqual(likely?.identifier, confirmed?.identifier)
    }

    func testDeliveredHistoryRejectsAlternatingDuplicateAfterEscalation() throws {
        var history = TiboAlertHistory()

        XCTAssertTrue(history.insert("tibo.likely.post-a"))
        XCTAssertTrue(history.insert("tibo.yes.post-a"))
        XCTAssertFalse(history.insert("tibo.likely.post-a"))

        let restored = try JSONDecoder().decode(
            TiboAlertHistory.self,
            from: JSONEncoder().encode(history)
        )
        XCTAssertTrue(restored.contains("tibo.likely.post-a"))
        XCTAssertTrue(restored.contains("tibo.yes.post-a"))
    }

    func testDeliveredHistoryStaysBounded() {
        var history = TiboAlertHistory(limit: 3)
        XCTAssertTrue(history.insert("one"))
        XCTAssertTrue(history.insert("two"))
        XCTAssertTrue(history.insert("three"))
        XCTAssertTrue(history.insert("four"))

        XCTAssertFalse(history.contains("one"))
        XCTAssertTrue(history.contains("four"))
    }

    private func post(id: String, text: String) -> TiboResetStatus.Post {
        TiboResetStatus.Post(
            text: text,
            id: id,
            createdAt: "2026-11-14T06:00:00Z",
            url: "https://x.com/thsottiaux/status/\(id)"
        )
    }

    private func signal(
        status: String,
        message: String = "Tracker message",
        fetchedAt: Int = 100,
        hintPost: TiboResetStatus.Post? = nil,
        latestPost: TiboResetStatus.Post? = nil,
        stale: Bool = false
    ) -> TiboResetStatus {
        TiboResetStatus(
            status: status,
            kind: nil,
            message: message,
            latestAt: nil,
            pendingAt: nil,
            fetchedAt: fetchedAt,
            source: "OpenTheRank",
            xSource: "@thsottiaux",
            latestPost: latestPost,
            hintPost: hintPost,
            probabilityToday: 80,
            probabilityBasis: "history+x",
            stale: stale
        )
    }
}
