import XCTest
@testable import MurmurDesign

final class ElapsedTimeTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(ElapsedTime.format(0), "0:00")
        XCTAssertEqual(ElapsedTime.format(7.9), "0:07")
        XCTAssertEqual(ElapsedTime.format(65), "1:05")
        XCTAssertEqual(ElapsedTime.format(765), "12:45")
        XCTAssertEqual(ElapsedTime.format(-3), "0:00")
        XCTAssertEqual(ElapsedTime.format(.nan), "0:00")
    }

    func testSpoken() {
        XCTAssertEqual(ElapsedTime.spoken(1), "1 second")
        XCTAssertEqual(ElapsedTime.spoken(42), "42 seconds")
        XCTAssertEqual(ElapsedTime.spoken(60), "1 minute")
        XCTAssertEqual(ElapsedTime.spoken(125), "2 minutes 5 seconds")
    }
}
