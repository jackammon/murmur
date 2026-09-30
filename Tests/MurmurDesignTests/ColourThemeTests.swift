import XCTest
@testable import MurmurDesign

final class ColourThemeTests: XCTestCase {
    func testEighteenThemesPlusOff() {
        XCTAssertEqual(ColourTheme.allCases.count, 19)
        XCTAssertNil(ColourTheme.off.field)
        let grouped = ColourTheme.groups.flatMap(\.themes)
        XCTAssertEqual(grouped.count, 18)
        XCTAssertEqual(Set(grouped), Set(ColourTheme.allCases).subtracting([.off]))
        XCTAssertEqual(Set(ColourTheme.allCases.map(\.title)).count, 19)
        XCTAssertEqual(ColourTheme(rawValue: "everyStill"), .everyStill)
    }

    /// Every cell takes a colour from the theme's palette (or, for Every
    /// still, from one of the stills).
    func testCellsUseOnlyThePalette() {
        for theme in ColourTheme.allCases {
            guard let field = theme.field else { continue }
            let allowed = Set(field.palette + ColourTheme.stills.flatMap { $0 })
            for t in [0.0, 2, 5.5, 13] {
                for (c, r) in sampleCells {
                    let colour = field.colour(u: (Double(c) + 0.5) / 38, v: (Double(r) + 0.5) / 12,
                                              aspect: 34.0 / 112, column: c, row: r, time: t)
                    XCTAssertTrue(allowed.contains(colour), "\(theme) at \(c),\(r)")
                }
            }
        }
    }

    func testFieldsShowSeveralColoursAndDuotoneExactlyTwo() {
        func colours(_ theme: ColourTheme) -> Set<RGB> {
            let field = theme.field!
            return Set(allCells.map { field.colour(u: (Double($0.0) + 0.5) / 38, v: (Double($0.1) + 0.5) / 12,
                                                   aspect: 34.0 / 112, column: $0.0, row: $0.1, time: 2) })
        }
        XCTAssertGreaterThanOrEqual(colours(.sunrise).count, 3)
        XCTAssertEqual(colours(.citrus).count, 2)
        XCTAssertGreaterThanOrEqual(colours(.sunriseHorizon).count, 2)
    }

    func testEveryStillMovesThroughTheStills() {
        let field = ColourTheme.everyStill.field!
        func palette(at t: Double) -> Set<RGB> {
            Set(allCells.map { field.colour(u: (Double($0.0) + 0.5) / 38, v: (Double($0.1) + 0.5) / 12,
                                            aspect: 34.0 / 112, column: $0.0, row: $0.1, time: t) })
        }
        let first = palette(at: 1), second = palette(at: ColourField.stillSeconds + 1)
        XCTAssertTrue(first.isSubset(of: Set(ColourTheme.stills[0])))
        XCTAssertTrue(second.isSubset(of: Set(ColourTheme.stills[1])))
    }

    func testInkAndHalo() {
        XCTAssertTrue(ColourTheme.sunrise.field!.lightInk)
        XCTAssertTrue(ColourTheme.sunrise.field!.halo)
        XCTAssertFalse(ColourTheme.blushWash.field!.lightInk)
        XCTAssertFalse(ColourTheme.sunriseRim.field!.halo)
        XCTAssertNotNil(ColourTheme.duskRim.field!.rim)
        XCTAssertEqual(ColourTheme.bigPixel.field!.cellSize, 6)
    }

    func testBayerCoversTheUnitInterval() {
        var seen = Set<Double>()
        for r in 0..<4 { for c in 0..<4 { seen.insert(Bayer.threshold(column: c, row: r)) } }
        XCTAssertEqual(seen.count, 16)
        XCTAssertTrue(seen.allSatisfy { $0 > 0 && $0 < 1 })
        XCTAssertEqual(Bayer.threshold(column: -1, row: -1), Bayer.threshold(column: 3, row: 3))
    }

    private let allCells: [(Int, Int)] = (0..<38).flatMap { c in (0..<12).map { (c, $0) } }
    private var sampleCells: [(Int, Int)] { stride(from: 0, to: allCells.count, by: 7).map { allCells[$0] } }
}
