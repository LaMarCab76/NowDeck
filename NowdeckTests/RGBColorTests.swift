import XCTest
@testable import Nowdeck

final class RGBColorTests: XCTestCase {
    func testParsesUppercaseAndLowercaseHex() throws {
        let upper = try XCTUnwrap(RGBColor(hex: "#2FD566"))
        let lower = try XCTUnwrap(RGBColor(hex: "#2fd566"))
        XCTAssertEqual(upper, lower)
        XCTAssertEqual(upper.red, 0x2F / 255, accuracy: 0.0001)
        XCTAssertEqual(upper.green, 0xD5 / 255, accuracy: 0.0001)
        XCTAssertEqual(upper.blue, 0x66 / 255, accuracy: 0.0001)
    }

    func testRejectsAnythingThatIsNotHashPlusSixHexDigits() {
        let invalid = ["", "#", "2FD566", "#FFF", "#2FD5667", "#2FD56G", "# 2FD56", "##2FD56", "#+FD566"]
        for value in invalid {
            XCTAssertNil(RGBColor(hex: value), "\(value) should be rejected")
        }
    }

    func testHexStringRoundTripsUppercased() throws {
        XCTAssertEqual(try XCTUnwrap(RGBColor(hex: "#a9b4c0")).hexString, "#A9B4C0")
        XCTAssertEqual(try XCTUnwrap(RGBColor(hex: "#000000")).hexString, "#000000")
        XCTAssertEqual(try XCTUnwrap(RGBColor(hex: "#FFFFFF")).hexString, "#FFFFFF")
    }
}
