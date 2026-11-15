import XCTest
@testable import CodexCockpit

final class VerificationCodeExtractorTests: XCTestCase {
    func testRanksEnglishAndVietnameseLabeledCodesFirst() {
        XCTAssertEqual(
            VerificationCodeExtractor.codes(
                subject: "Verification code: A7K29Q",
                body: "Mã xác minh của bạn là 482731. Reference 7391."
            ),
            ["A7K29Q", "482731", "7391"]
        )
    }

    func testDeduplicatesAndReturnsAtMostFiveCandidates() {
        XCTAssertEqual(
            VerificationCodeExtractor.codes(
                subject: "Code 1111",
                body: "OTP 1111, backup 2222 3333 4444 5555 6666 7777"
            ),
            ["1111", "2222", "3333", "4444", "5555"]
        )
    }

    func testRejectsDatesPricesPhonesAndLongIdentifiers() {
        XCTAssertEqual(
            VerificationCodeExtractor.codes(
                subject: "Receipt dated 2026-11-15",
                body: "Total $1299.00. Phone 0901 234 567. Order 123456789012. Your OTP is 884422."
            ),
            ["884422"]
        )
    }

    func testSanitizerUsesPlainTextWithoutInterpretingHTML() {
        let result = MailTextSanitizer.plainText(
            text: "  Hello <b>literal</b>  ",
            html: ["<p>ignored</p>"]
        )

        XCTAssertEqual(result, "Hello <b>literal</b>")
    }

    func testSanitizerBuildsInertTextFromHTMLOnlyMessage() {
        let result = MailTextSanitizer.plainText(
            text: nil,
            html: [
                "<style>.hidden{display:none}</style><p>Hello&nbsp;<strong>friend</strong></p>",
                "<script>steal()</script><div>Code: &#52;&#56;&#50;&#55;&#51;&#49;</div>"
            ]
        )

        XCTAssertEqual(result, "Hello friend\nCode: 482731")
        XCTAssertFalse(result.contains("steal"))
        XCTAssertFalse(result.contains("display:none"))
    }

    func testSanitizerCapsHostileMessageLength() {
        let result = MailTextSanitizer.plainText(
            text: String(repeating: "A", count: MailTextSanitizer.maximumLength + 500),
            html: []
        )

        XCTAssertEqual(result.count, MailTextSanitizer.maximumLength)
    }
}
