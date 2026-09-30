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

final class VersionTextTests: XCTestCase {
    func testDisplay() {
        XCTAssertEqual(VersionText.display("1.0.0"), "1")
        XCTAssertEqual(VersionText.display("1.2.0"), "1.2")
        XCTAssertEqual(VersionText.display("1.2.3"), "1.2.3")
        XCTAssertEqual(VersionText.display("10.0"), "10")
        XCTAssertEqual(VersionText.display("2.0.0-alpha.3"), "2.0.0-alpha.3")
    }
}
