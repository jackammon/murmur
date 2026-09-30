import XCTest
@testable import MurmurDesign

final class DotGridTests: XCTestCase {
    let grid = DotGrid.hud

    func testDimensionsAreOddWithACentre() {
        XCTAssertEqual(grid.columns, 11)
        XCTAssertEqual(grid.rows, 7)
        XCTAssertEqual(DotGrid(columns: 10, rows: 8).columns, 9)
        XCTAssertEqual(DotGrid(columns: 10, rows: 8).rows, 7)
        XCTAssertEqual(DotGrid(columns: 0, rows: 0).allDots.count, 1)
        XCTAssertEqual(grid.centreColumn, 5)
        XCTAssertEqual(grid.centreRow, 3)
    }

    func testSpansAreCentredAndNeverEmpty() {
        XCTAssertEqual(grid.span(height: 0), 3..<4)
        XCTAssertEqual(grid.span(height: 1), 0..<7)
        XCTAssertEqual(grid.span(height: 3.0 / 7), 2..<5)
        XCTAssertEqual(grid.span(height: 5), 0..<7)
    }

    func testNewestLevelFillsTheCentre() {
        var levels = [Float](repeating: 0, count: 11)
        levels[10] = 1
        let heights = grid.liveHeights(levels: levels)
        XCTAssertEqual(heights[5], 1, accuracy: 1e-9)
        XCTAssertEqual(heights[0], grid.floorHeight, accuracy: 1e-9)
        XCTAssertEqual(heights[10], grid.floorHeight, accuracy: 1e-9)
        // Symmetric around the centre.
        let ripple = grid.liveHeights(levels: (0..<11).map { Float($0) / 10 })
        for i in 0..<5 { XCTAssertEqual(ripple[i], ripple[10 - i], accuracy: 1e-9) }
    }

    func testSilenceIsADottedLine() {
        let dots = grid.lit(heights: grid.liveHeights(levels: []))
        XCTAssertEqual(dots.count, 11)
        XCTAssertTrue(dots.allSatisfy { $0.row == 3 })
    }

    func testQuietLineIsTheCentreRow() {
        XCTAssertEqual(grid.quietLine.count, 11)
        XCTAssertTrue(grid.quietLine.allSatisfy { $0.row == 3 })
    }

    func testWorkingHeightsStayInRange() {
        for t in stride(from: 0.0, to: 5, by: 0.13) {
            for h in grid.workingHeights(time: t) {
                XCTAssertGreaterThan(h, 0.1)
                XCTAssertLessThanOrEqual(h, 0.5)
            }
        }
    }

    func testAlertIsAnExclamationMark() {
        let alert = grid.alert
        XCTAssertTrue(alert.allSatisfy { $0.column == 5 })
        let rows = alert.map(\.row).sorted()
        XCTAssertEqual(rows, [0, 1, 2, 3, 5])
    }
}

final class PasteAnimationTests: XCTestCase {
    let grid = DotGrid.hud
    let wave = DotGrid.hud.liveHeights(levels: [0.2, 0.5, 0.9, 0.6, 0.8, 0.4, 0.7, 0.3, 0.9, 0.5, 0.6])

    func testDefaultIsFillAndDissolve() {
        XCTAssertEqual(PasteAnimation.default, .fillAndDissolve)
        XCTAssertEqual(PasteAnimation(rawValue: "star"), .star)
    }

    func testFillAndDissolveGrowsFillsThenEmpties() {
        let a = PasteAnimation.fillAndDissolve
        XCTAssertEqual(a.lit(in: grid, progress: 0, from: wave), [Dot(column: 5, row: 3)])
        XCTAssertEqual(a.lit(in: grid, progress: 0.38, from: wave).count, grid.allDots.count)
        let mid = a.lit(in: grid, progress: 0.6, from: wave).count
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, grid.allDots.count)
        XCTAssertTrue(a.lit(in: grid, progress: 0.85, from: wave).isEmpty)
    }

    func testStarGathersShootsOutAndEmpties() {
        let a = PasteAnimation.star
        XCTAssertEqual(a.lit(in: grid, progress: 0, from: wave), grid.lit(heights: wave))
        XCTAssertEqual(a.lit(in: grid, progress: 0.199, from: wave).count, 1)
        let star = a.lit(in: grid, progress: 0.55, from: wave)
        XCTAssertTrue(star.contains(Dot(column: 0, row: 3)))
        XCTAssertTrue(star.contains(Dot(column: 10, row: 3)))
        XCTAssertTrue(star.contains(Dot(column: 5, row: 0)))
        XCTAssertFalse(star.contains(Dot(column: 0, row: 0)))
        XCTAssertTrue(a.lit(in: grid, progress: 0.9, from: wave).isEmpty)
    }

    func testHudHoldsThenFadesTogether() {
        XCTAssertEqual(PasteAnimation.hudOpacity(progress: 0), 1)
        XCTAssertEqual(PasteAnimation.hudOpacity(progress: PasteAnimation.fadeStart), 1)
        let mid = PasteAnimation.hudOpacity(progress: 0.86)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
        XCTAssertEqual(PasteAnimation.hudOpacity(progress: 1), 0, accuracy: 1e-9)
    }

    func testEveryFrameStaysInsideTheGrid() {
        for animation in PasteAnimation.allCases {
            for p in stride(from: 0.0, through: 1.0, by: 0.02) {
                for dot in animation.lit(in: grid, progress: p, from: wave) {
                    XCTAssertTrue((0..<grid.columns).contains(dot.column))
                    XCTAssertTrue((0..<grid.rows).contains(dot.row))
                }
            }
        }
    }

    func testHUDStyle() {
        XCTAssertTrue(HUDStyle.dark.isDark(systemIsDark: false))
        XCTAssertFalse(HUDStyle.light.isDark(systemIsDark: true))
        XCTAssertTrue(HUDStyle.system.isDark(systemIsDark: true))
        XCTAssertFalse(HUDStyle.system.isDark(systemIsDark: false))
    }
}

final class LeanMarkTests: XCTestCase {
    func testPillsFitTheBox() {
        for pill in LeanMark.pills {
            let (x0, y0, x1, y1) = LeanMark.bounds(of: pill)
            XCTAssertGreaterThanOrEqual(x0, 0)
            XCTAssertGreaterThanOrEqual(y0, 0)
            XCTAssertLessThanOrEqual(x1, LeanMark.width + 0.25)
            XCTAssertLessThanOrEqual(y1, LeanMark.height)
        }
    }

    func testListeningPillsFollowLevelsAndKeepTheirPlace() {
        let quiet = LeanMark.pills(levels: Array(repeating: 0, count: 11))
        let loud = LeanMark.pills(levels: Array(repeating: 1, count: 11))
        XCTAssertEqual(loud, LeanMark.pills)
        for (q, rest) in zip(quiet, LeanMark.pills) {
            XCTAssertLessThan(q.length, rest.length)
            XCTAssertGreaterThanOrEqual(q.length, LeanMark.thickness)
            XCTAssertEqual(q.centreX, rest.centreX)
        }
        XCTAssertEqual(LeanMark.pills(levels: []), LeanMark.pills)
    }
}
