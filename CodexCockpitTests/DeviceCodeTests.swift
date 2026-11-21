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
    }

    func testRejectsGarbageAndShortInput() {
        XCTAssertNil(DeviceCode.parse("!@#$%^"))
        XCTAssertNil(DeviceCode.parse("ABC"))
        XCTAssertNil(DeviceCode.extract(from: "Không có mã ở đây."))
    }

    func testRemovesUnderscoreAndEmojiWithoutCorrectingCharacters() {
        XCTAssertEqual(DeviceCode.normalize("ab_cd🔑efghi"), "ABCD-EFGHI")
        XCTAssertEqual(DeviceCode.parse("ab_cd🔑efghi"), DeviceCode(value: "ABCD-EFGHI"))
        XCTAssertEqual(DeviceCode.normalize("O0o0-1I1i"), "O0O0-1I1I")
    }
}
