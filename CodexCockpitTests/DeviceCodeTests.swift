import XCTest
@testable import CodexCockpit

final class DeviceCodeTests: XCTestCase {
    func testNormalizesSpacesAndAddsSeparator() {
        XCTAssertEqual(DeviceCode.normalize("abcd efghi"), "ABCD-EFGHI")
        XCTAssertEqual(DeviceCode.parse("abcd efghi"), DeviceCode(value: "ABCD-EFGHI"))
    }

    func testParsesEightCharacterCode() {
        XCTAssertEqual(DeviceCode.parse("ABCD-EFGH"), DeviceCode(value: "ABCD-EFGH"))
    }

    func testExtractsCodeFromClipboardSentence() {
        XCTAssertEqual(
            DeviceCode.extract(from: "Your code: WXYZ-12345."),
            DeviceCode(value: "WXYZ-12345")
        )
        XCTAssertEqual(
            DeviceCode.extract(from: "WXYZ-12345 is your code"),
            DeviceCode(value: "WXYZ-12345")
        )
    }

    func testRejectsGarbageAndShortInput() {
        XCTAssertNil(DeviceCode.parse("!@#$%^"))
        XCTAssertNil(DeviceCode.parse("ABC"))
        XCTAssertNil(DeviceCode.extract(from: "Không có mã ở đây."))
        for text in ["Thank you", "Code: ABCD", "password", "open this"] {
            XCTAssertNil(DeviceCode.extract(from: text), text)
        }
    }

    func testRemovesUnderscoreAndEmojiWithoutCorrectingCharacters() {
        XCTAssertEqual(DeviceCode.normalize("ab_cd🔑efghi"), "ABCD-EFGHI")
        XCTAssertEqual(DeviceCode.parse("ab_cd🔑efghi"), DeviceCode(value: "ABCD-EFGHI"))
        XCTAssertEqual(DeviceCode.normalize("O0o0-1I1i"), "O0O0-1I1I")
    }

    func testNormalizeLimitsCodeToNineAlphanumericCharacters() {
        XCTAssertEqual(DeviceCode.normalize("abcd-123456789"), "ABCD-12345")
    }

    func testExtractionDoesNotTreatTwoWordsAsCode() {
        XCTAssertNil(DeviceCode.extract(from: "ABCD EFGH"))
        XCTAssertEqual(DeviceCode.extract(from: "Use token ABCD1234 now"), DeviceCode(value: "ABCD-1234"))
        XCTAssertNil(DeviceCode.extract(from: "Use token ABCDEFGH now"))
    }
}
