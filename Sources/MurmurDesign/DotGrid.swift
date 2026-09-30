import Foundation

// The listening HUD and the popover's live wave are a small grid of round
// dots ("round stipple"). Columns stand for slices of sound: the newest level
// sits in the centre column and older levels ripple outward. This file holds
// the rules only — which dots are lit — with no AppKit or SwiftUI, so every
// renderer agrees and the rules can be unit tested.

/// One dot in a `DotGrid`. Row 0 is the top row.
public struct Dot: Hashable, Sendable {
    public let column: Int
    public let row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// A grid of dots with a centre column and a centre row.
public struct DotGrid: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    /// The HUD's grid: 11 columns by 7 rows.
    public static let hud = DotGrid(columns: 11, rows: 7)

    /// Both dimensions are forced odd so the grid has a centre dot.
    public init(columns: Int, rows: Int) {
        let c = max(1, columns)
        let r = max(1, rows)
        self.columns = c % 2 == 0 ? c - 1 : c
        self.rows = r % 2 == 0 ? r - 1 : r
    }

    public var centreColumn: Int { columns / 2 }
    public var centreRow: Int { rows / 2 }

    public var allDots: [Dot] {
        (0..<columns).flatMap { c in (0..<rows).map { Dot(column: c, row: $0) } }
    }

    // MARK: - Heights

    /// Shortest a column gets, so silence still reads as a dotted line.
    public var floorHeight: Double { 1 / Double(rows) }

    /// Distance of `column` from the centre: 0 at the centre, 1 at the edges.
    public func distanceFromCentre(_ column: Int) -> Double {
        let centre = Double(centreColumn)
        guard centre > 0 else { return 0 }
        return abs(Double(column) - centre) / centre
    }

    /// Column heights (0…1) for live input. `levels` are 0…1, oldest first,
    /// as `AppState.levelHistory` keeps them. The newest level fills the
    /// centre column and older levels spread to both edges, tapering a little.
    public func liveHeights(levels: [Float]) -> [Double] {
        guard let newest = levels.indices.last else {
            return Array(repeating: floorHeight, count: columns)
        }
        let reach = Double(min(newest, 7))
        return (0..<columns).map { column in
            let d = distanceFromCentre(column)
            let index = newest - Int((d * reach).rounded())
            let level = Double(levels[max(0, index)])
            return max(floorHeight, level * (1 - 0.35 * d * d))
        }
    }

    /// A slow swell travelling through the grid, for transcribing and polishing.
    public func workingHeights(time: Double) -> [Double] {
        (0..<columns).map { column in
            let d = distanceFromCentre(column)
            let wave = 0.5 + 0.5 * sin(time * 2.6 - Double(column) * 0.5)
            return 0.14 + 0.36 * (1 - 0.5 * d * d) * wave * wave
        }
    }

    // MARK: - Lit dots

    /// Number of dots a column of `height` lights, at least one.
    public func litCount(height: Double) -> Int {
        min(rows, max(1, Int((height * Double(rows)).rounded())))
    }

    /// Rows lit by a column of `height`, centred vertically.
    public func span(height: Double) -> Range<Int> {
        let lit = litCount(height: height)
        let top = (rows - lit) / 2
        return top..<(top + lit)
    }

    /// Dots lit by a set of column heights.
    public func lit(heights: [Double]) -> Set<Dot> {
        var dots = Set<Dot>()
        for (column, height) in heights.prefix(columns).enumerated() {
            for row in span(height: height) { dots.insert(Dot(column: column, row: row)) }
        }
        return dots
    }

    /// A single dotted line along the centre row.
    public var quietLine: Set<Dot> {
        Set((0..<columns).map { Dot(column: $0, row: centreRow) })
    }

    /// An exclamation mark in the centre column, for errors.
    public var alert: Set<Dot> {
        let stroke = 0..<max(1, rows - 3)
        var dots = Set(stroke.map { Dot(column: centreColumn, row: $0) })
        dots.insert(Dot(column: centreColumn, row: rows - 2))
        return dots
    }

    // MARK: - Geometry helpers

    /// Elliptical distance from the centre dot: 0 at the centre, 1 at the
    /// midpoint of each edge, about 1.41 in the corners.
    public func ellipticalDistance(_ dot: Dot) -> Double {
        let cx = Double(max(1, centreColumn)), cy = Double(max(1, centreRow))
        return hypot(Double(dot.column - centreColumn) / cx, Double(dot.row - centreRow) / cy)
    }
}

// MARK: - Paste animations

/// What the HUD plays when text lands at the cursor. Chosen in Settings →
/// General → Appearance; Fill and dissolve is the default.
public enum PasteAnimation: String, CaseIterable, Sendable {
    /// The grid floods with dots from the centre, holds, then the dots wink
    /// out in a scattered order.
    case fillAndDissolve
    /// The dots gather to the centre, a four-pointed star shoots out to the
    /// grid's edges, and its arms run off the ends.
    case star

    public static let defaultsKey = "murmur.pasteAnimation"
    public static let `default` = PasteAnimation.fillAndDissolve

    /// Seconds from paste to the HUD being fully gone.
    public static let duration: Double = 1.0
    /// Fraction of `duration` at which the whole HUD — surface, dots and
    /// clock together — starts to fade.
    public static let fadeStart: Double = 0.72

    public var title: String {
        switch self {
        case .fillAndDissolve: "Fill and dissolve"
        case .star: "Star"
        }
    }

    /// HUD opacity at `progress` (0…1): full until `fadeStart`, then eases to 0.
    public static func hudOpacity(progress: Double) -> Double {
        let t = clamp((progress - fadeStart) / (1 - fadeStart))
        return 1 - (1 - pow(1 - t, 3))
    }

    /// Dots lit at `progress` (0…1). `heights` is the wave at the moment of
    /// paste, which the star gathers from.
    public func lit(in grid: DotGrid, progress p: Double, from heights: [Double]) -> Set<Dot> {
        switch self {
        case .fillAndDissolve:
            return Set(grid.allDots.filter { dot in
                if p < 0.32 {
                    return grid.ellipticalDistance(dot) <= easeOut(p / 0.3) * 1.45
                }
                return DotNoise.unit(dot.column, dot.row, 3) > (p - 0.42) / 0.38
            })
        case .star:
            if p < 0.2 {
                return Self.gathered(grid, from: heights, amount: easeIn(p / 0.2))
            }
            let reach = easeOut((p - 0.2) / 0.35) * 1.2
            let hollow = easeIn((p - 0.55) / 0.3) * 1.25
            return Set(grid.allDots.filter { dot in
                guard Self.isOnStar(dot, in: grid) else { return false }
                let d = grid.ellipticalDistance(dot)
                return d <= reach && d >= hollow
            })
        }
    }

    /// The centre row, the centre column, and two short diagonals each way.
    static func isOnStar(_ dot: Dot, in grid: DotGrid) -> Bool {
        let dx = abs(dot.column - grid.centreColumn)
        let dy = abs(dot.row - grid.centreRow)
        return dy == 0 || dx == 0 || (dx == dy && dx <= 2) || (dx == dy * 2 && dy <= 1)
    }

    /// The lit dots contracting towards the centre dot (`amount` 0…1).
    static func gathered(_ grid: DotGrid, from heights: [Double], amount: Double) -> Set<Dot> {
        let maxDX = Int((Double(grid.centreColumn) * (1 - amount)).rounded())
        let maxDY = Int((Double(grid.centreRow) * (1 - amount)).rounded())
        var dots = grid.lit(heights: heights).filter {
            abs($0.column - grid.centreColumn) <= maxDX && abs($0.row - grid.centreRow) <= maxDY
        }
        if dots.isEmpty { dots.insert(Dot(column: grid.centreColumn, row: grid.centreRow)) }
        return dots
    }
}

/// HUD surface. Chosen in Settings → General → Appearance.
public enum HUDStyle: String, CaseIterable, Sendable {
    case dark
    case light
    case system

    public static let defaultsKey = "murmur.hudStyle"

    public var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Match system"
        }
    }

    /// Whether the HUD draws dark, given the system appearance.
    public func isDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .dark: true
        case .light: false
        case .system: systemIsDark
        }
    }
}

// MARK: - Helpers

/// Deterministic hash noise, 0 ≤ value < 1.
public enum DotNoise {
    public static func unit(_ a: Int, _ b: Int, _ c: Int) -> Double {
        var x = UInt32(truncatingIfNeeded: a &* 73_856_093)
            ^ UInt32(truncatingIfNeeded: b &* 19_349_663)
            ^ UInt32(truncatingIfNeeded: c &* 83_492_791)
        x = (x ^ (x >> 16)) &* 0x7feb_352d
        x = (x ^ (x >> 15)) &* 0x846c_a68b
        x = x ^ (x >> 16)
        return Double(x) / 4_294_967_296
    }
}

func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
func easeIn(_ x: Double) -> Double { pow(clamp(x), 2) }
