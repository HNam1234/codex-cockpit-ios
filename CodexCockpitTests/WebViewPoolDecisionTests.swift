import Foundation
import XCTest
@testable import CodexCockpit

final class WebViewPoolDecisionTests: XCTestCase {
    private let chatGPT = URL(string: "https://chatgpt.com/")!
    private let device = URL(string: "https://auth.openai.com/codex/device")!
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testChatGPTToDeviceLoadsRequestedPage() {
        XCTAssertEqual(decision(current: chatGPT, requested: device), .load)
    }

    func testDeviceToChatGPTLoadsRequestedPage() {
        XCTAssertEqual(decision(current: device, requested: chatGPT), .load)
    }

    func testFreshDevicePageIsKept() {
        XCTAssertEqual(
            decision(current: device, requested: device, age: 9 * 60),
            .keep
        )
    }

    func testStaleDevicePageReloads() {
        XCTAssertEqual(
            decision(current: device, requested: device, age: 11 * 60),
            .reload
        )
    }

    func testMissingCurrentPageLoadsRequestedPage() {
        XCTAssertEqual(decision(current: nil, requested: device), .load)
    }

    func testSameChatGPTPageIsKept() {
        XCTAssertEqual(decision(current: chatGPT, requested: chatGPT), .keep)
    }

    private func decision(
        current: URL?,
        requested: URL,
        age: TimeInterval? = nil
    ) -> WebViewPool.NavigationDecision {
        WebViewPool.shouldNavigate(
            current: current,
            requested: requested,
            lastFinishedAt: age.map { now.addingTimeInterval(-$0) },
            now: now
        )
    }
}
