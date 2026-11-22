import XCTest
@testable import Livo

final class MoneyTests: XCTestCase {
    func testFormatBRL() {
        let s = Money.format(123456).replacingOccurrences(of: "\u{00A0}", with: " ")
        XCTAssertEqual(s, "R$ 1.234,56")
    }

    func testParse() {
        XCTAssertEqual(Money.parse("75"), 7500)
        XCTAssertEqual(Money.parse("75,5"), 7550)
        XCTAssertEqual(Money.parse("1.234,56"), 123456)
        XCTAssertEqual(Money.parse("R$ 1.234,56"), 123456)
        XCTAssertEqual(Money.parse("-10,00"), -1000)
        XCTAssertEqual(Money.parse(",99"), 99)
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("abc"))
        XCTAssertNil(Money.parse("1,2,3"))
    }

    func testRoundTrip() {
        for cents: Int64 in [0, 1, 99, 100, 7500, 123456, 99_999_999] {
            XCTAssertEqual(Money.parse(Money.format(cents)), cents)
        }
    }
}
