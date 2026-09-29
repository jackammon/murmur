import XCTest
@testable import MurmurKit

final class MurmurKitTests: XCTestCase {
    func testVersionExists() {
        XCTAssertFalse(MurmurKit.version.isEmpty)
    }
}
