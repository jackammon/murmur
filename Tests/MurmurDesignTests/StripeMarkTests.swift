import XCTest
@testable import MurmurDesign

final class StripeMarkTests: XCTestCase {
    func testCellsStayInsideTheBox() {
        for (w, h) in [(634.0, 572.0), (80.0, 72.0), (16.0, 14.0)] {
            let cells = StripeMark.cells(width: w, height: h, snap: w < 100)
            XCTAssertFalse(cells.isEmpty)
            for c in cells {
                XCTAssertGreaterThanOrEqual(c.x, -1e-9)
                XCTAssertGreaterThanOrEqual(c.y, -1e-9)
                XCTAssertLessThanOrEqual(c.x + c.width, w + 1e-9)
                XCTAssertLessThanOrEqual(c.y + c.height, h + 1e-9)
            }
        }
    }

    func testSnappedCellsAreWholePixelsAndNeverEmpty() {
        for c in StripeMark.cells(width: 16, height: 14, snap: true) {
            XCTAssertEqual(c.x, c.x.rounded())
            XCTAssertEqual(c.width, c.width.rounded())
            XCTAssertGreaterThanOrEqual(c.width, 1)
            XCTAssertGreaterThanOrEqual(c.height, 1)
        }
    }

    func testMarkIsStableAndUsesSeveralColours() {
        let a = StripeMark.cells(width: 200, height: 180)
        XCTAssertEqual(a, StripeMark.cells(width: 200, height: 180))
        XCTAssertGreaterThanOrEqual(Set(a.map { "\($0.color)" }).count, 5)
    }

    func testSmallMarksUseACoarserGrid() {
        XCTAssertEqual(StripeMark.grid(forWidth: 10).columns, 5)
        XCTAssertEqual(StripeMark.grid(forWidth: 12).columns, 7)
        XCTAssertGreaterThan(StripeMark.scale(forTileSide: 12).width,
                             StripeMark.scale(forTileSide: 824).width)
        XCTAssertEqual(StripeMark.grid(forWidth: 600).columns, 9)
    }
}
