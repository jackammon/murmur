import XCTest
@testable import MurmurKit

final class PolishEngineKindTests: XCTestCase {
    func testParsesKnownRawValues() {
        XCTAssertEqual(PolishEngineKind(rawValue: "off"), .off)
        XCTAssertEqual(PolishEngineKind(rawValue: "llamaCpp"), .llamaCpp)
    }

    func testUnknownRawValueIsNil() {
        XCTAssertNil(PolishEngineKind(rawValue: "mlx"))
    }

    func testAllCasesCovered() {
        XCTAssertEqual(Set(PolishEngineKind.allCases), [.off, .llamaCpp])
    }
}
