import XCTest
@testable import MurmurDesign

final class StripeFieldTests: XCTestCase {
    func testFieldForcesOddColumnsAndEvenRows() {
        let field = StripeField(columns: 8, rows: 15)
        XCTAssertEqual(field.columns, 7)
        XCTAssertEqual(field.rows, 14)
        XCTAssertEqual(StripeField(columns: 0, rows: 0).columns, 1)
        XCTAssertEqual(StripeField(columns: 0, rows: 0).rows, 2)
    }

    func testRestingMarkIsSymmetricAndPeaksInTheCentre() {
        let field = StripeField(columns: 7, rows: 16)
        let heights = field.heights(for: .resting)
        XCTAssertEqual(heights.count, 7)
        for i in 0..<3 {
            XCTAssertEqual(heights[i], heights[6 - i], accuracy: 1e-9)
            XCTAssertLessThan(heights[i], heights[i + 1])
        }
        XCTAssertEqual(heights[3], 1, accuracy: 1e-9)
    }

    func testRestingMarkBreaksEachTallColumnExactlyOnce() {
        let field = StripeField(columns: 7, rows: 16)
        let rows = field.litRows(for: .resting)
        for (column, lit) in rows.enumerated() {
            let span = field.litCount(for: field.heights(for: .resting)[column])
            if span >= 6 {
                XCTAssertEqual(lit.count, span - 1, "column \(column)")
                XCTAssertNotEqual(lit.first, lit.last.map { $0 - lit.count + 1 },
                                  "column \(column) should contain a gap")
            } else {
                XCTAssertEqual(lit.count, span, "column \(column)")
            }
        }
        // Stable: the brand mark never changes with time.
        XCTAssertEqual(rows, field.litRows(for: .resting, time: 42))
    }

    func testLiveLevelsPutTheNewestSampleInTheCentre() {
        let field = StripeField(columns: 9, rows: 20)
        let heights = field.heights(for: .live([0, 0, 0, 1]))
        let centre = heights[4]
        XCTAssertGreaterThan(centre, 0.85)
        XCTAssertEqual(heights[0], StripeField.floor, accuracy: 1e-9)
        XCTAssertEqual(heights[8], StripeField.floor, accuracy: 1e-9)
    }

    func testSilenceStillDrawsADottedLine() {
        let field = StripeField(columns: 5, rows: 10)
        let rows = field.litRows(for: .live([0, 0, 0]), time: 3)
        XCTAssertTrue(rows.allSatisfy { $0 == [4, 5] })
    }

    func testLiveBreaksFlickerOnlyWhenAllowed() {
        let field = StripeField(columns: 15, rows: 24)
        let levels: [Float] = Array(repeating: 0.9, count: 11)
        let still0 = field.litRows(for: .live(levels), time: 0.0, flicker: false)
        let still1 = field.litRows(for: .live(levels), time: 0.5, flicker: false)
        // Heights shimmer slightly with time, so compare the break pattern on
        // the centre column, whose height stays at the cap.
        XCTAssertEqual(still0[7], still1[7])
        let a = field.litRows(for: .live(levels), time: 0.0)
        let b = field.litRows(for: .live(levels), time: 0.5)
        XCTAssertNotEqual(a, b)
    }

    func testQuietAndAlert() {
        let field = StripeField(columns: 7, rows: 16)
        XCTAssertTrue(field.litRows(for: .quiet).allSatisfy { $0 == [7, 8] })
        let alert = field.litRows(for: .alert)
        XCTAssertEqual(alert[0], [7, 8])
        XCTAssertEqual(alert[2], [])
        XCTAssertEqual(alert[4], [])
        let centre = alert[3]
        XCTAssertGreaterThan(centre.count, 6)
        // Stroke, then a gap, then the dot.
        let gaps = zip(centre, centre.dropFirst()).filter { $1 - $0 > 1 }
        XCTAssertEqual(gaps.count, 1)
        XCTAssertLessThanOrEqual(centre.max() ?? 99, 15)
    }

    func testWorkingHeightsStayInsideTheField() {
        let field = StripeField(columns: 11, rows: 12)
        for t in stride(from: 0.0, to: 3.0, by: 0.1) {
            for h in field.heights(for: .working, time: t) {
                XCTAssertGreaterThanOrEqual(h, 0)
                XCTAssertLessThanOrEqual(h, 1)
            }
            for column in field.litRows(for: .working, time: t) {
                XCTAssertTrue(column.allSatisfy { (0..<12).contains($0) })
            }
        }
    }
}

final class StripePaletteTests: XCTestCase {
    func testDitherThresholdsCoverTheUnitIntervalOnce() {
        var seen: [Double] = []
        for r in 0..<4 { for c in 0..<4 { seen.append(OrderedDither.threshold(column: c, row: r)) } }
        XCTAssertEqual(Set(seen).count, 16)
        XCTAssertTrue(seen.allSatisfy { $0 > 0 && $0 < 1 })
        XCTAssertEqual(OrderedDither.threshold(column: -1, row: -1),
                       OrderedDither.threshold(column: 3, row: 3))
    }

    func testStillMarksUseTheFirstSceneWarmToCool() {
        // Left edge in magenta/coral, right edge in green/teal/aqua.
        let left = StripePalette.index(column: 0, row: 5, columns: 9, rows: 10)
        let right = StripePalette.index(column: 8, row: 5, columns: 9, rows: 10)
        XCTAssertTrue((0...2).contains(left), "left \(left)")
        XCTAssertTrue((5...7).contains(right), "right \(right)")
    }

    func testScenesHoldThenDissolve() {
        let s = StripePalette.sceneSeconds
        let hold = s - StripePalette.dissolveSeconds
        XCTAssertEqual(StripePalette.sceneBlend(at: 0.1).amount, 0)
        XCTAssertEqual(StripePalette.sceneBlend(at: hold - 0.01).amount, 0)
        let mid = StripePalette.sceneBlend(at: hold + StripePalette.dissolveSeconds / 2)
        XCTAssertEqual(mid.from, 0)
        XCTAssertEqual(mid.to, 1)
        XCTAssertEqual(mid.amount, 0.5, accuracy: 1e-9)
        XCTAssertEqual(StripePalette.sceneBlend(at: s + 0.1).from, 1)
        // Wraps back to the first scene.
        let count = Double(StripePalette.scenes.count)
        XCTAssertEqual(StripePalette.sceneBlend(at: s * count + 0.1).from, 0)
        XCTAssertEqual(StripePalette.sceneBlend(at: s * (count - 1) + 0.1).to, 0)
    }

    func testColoursChangeFromSceneToScene() {
        func sceneOf(_ index: Int) -> Int {
            var offset = 0
            for (i, scene) in StripePalette.scenes.enumerated() {
                if index < offset + scene.count { return i }
                offset += scene.count
            }
            return -1
        }
        let s = StripePalette.sceneSeconds
        let cells = (0..<15).flatMap { c in (0..<12).map { r in (c, r) } }
        let first = Set(cells.map { sceneOf(StripePalette.index(column: $0.0, row: $0.1, columns: 15, rows: 12, time: 1)) })
        let second = Set(cells.map { sceneOf(StripePalette.index(column: $0.0, row: $0.1, columns: 15, rows: 12, time: s + 1)) })
        XCTAssertEqual(first, [0])
        XCTAssertEqual(second, [1])
        // Mid-dissolve, both scenes show at once.
        let mixing = Set(cells.map { sceneOf(StripePalette.index(column: $0.0, row: $0.1, columns: 15, rows: 12,
                                                                  time: s - StripePalette.dissolveSeconds / 2)) })
        XCTAssertEqual(mixing, [0, 1])
    }

    func testPaletteIndexIsAlwaysValid() {
        for t in stride(from: 0.0, to: 60.0, by: 0.37) {
            for c in 0..<15 {
                for r in 0..<12 {
                    let i = StripePalette.index(column: c, row: r, columns: 15, rows: 12, time: t)
                    XCTAssertTrue(StripePalette.stops.indices.contains(i))
                }
            }
        }
        XCTAssertTrue(StripePalette.stops.indices.contains(
            StripePalette.index(column: 3, row: 3, columns: 9, rows: 9, time: 8e8)))
    }

    func testHexParsing() {
        let c = StripeColor(hex: 0xFF8000)
        XCTAssertEqual(c.red, 1)
        XCTAssertEqual(c.green, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(c.blue, 0)
    }
}

final class StripeLayoutTests: XCTestCase {
    func testFittedLayoutCentresOnWholePoints() {
        let layout = StripeLayout.fitted(width: 46, height: 24, bar: 2, gap: 2, cell: 2)
        XCTAssertEqual(layout.field.columns, 11)   // (46 + 2) / 4 = 12 → odd 11
        XCTAssertEqual(layout.field.rows, 12)
        XCTAssertEqual(layout.originX, 2)          // used 11 · 4 − 2 = 42
        XCTAssertEqual(layout.originY, 0)
        let odd = StripeLayout.fitted(width: 45, height: 25, bar: 2, gap: 2, cell: 2)
        XCTAssertEqual(odd.originX, odd.originX.rounded())
        XCTAssertEqual(odd.originY, odd.originY.rounded())
        // 26 pt at 2 pt rows is 13 rows; rounding down keeps the field inside.
        let tile = StripeLayout.fitted(width: 58, height: 26, bar: 2, gap: 2, cell: 2)
        XCTAssertEqual(tile.field.rows, 12)
        XCTAssertGreaterThanOrEqual(tile.originY, 0)
    }

    func testProportionalLayoutFillsTheWidth() {
        let layout = StripeLayout.proportional(width: 100, height: 60, columns: 9, rows: 22)
        let last = layout.rect(column: 8, row: 21)
        XCTAssertEqual(layout.rect(column: 0, row: 0).x, 0, accuracy: 1e-9)
        XCTAssertEqual(last.x + last.width, 100, accuracy: 1e-9)
        XCTAssertEqual(last.y + last.height, 60, accuracy: 1e-9)
    }

    func testStyles() {
        XCTAssertEqual(StripeStyle(rawValue: "color"), .color)
        XCTAssertTrue(StripeStyle.color.usesPalette)
        XCTAssertFalse(StripeStyle.whiteOnBlack.usesPalette)
        XCTAssertTrue(StripeStyle.whiteOnBlack.hasDarkSurface)
        XCTAssertFalse(StripeStyle.blackOnWhite.hasDarkSurface)
    }
}
