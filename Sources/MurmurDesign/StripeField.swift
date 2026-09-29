import Foundation

// Murmur's visual system draws every mark — the menu-bar glyph, the listening
// HUD, the popover header, and the app icon — as a field of short vertical
// segments on a grid. Columns stand for slices of sound; small breaks in each
// column give the stripes their texture. This file holds the geometry and
// colour math only, with no AppKit or SwiftUI, so the renderers share one
// source of truth and the rules can be unit tested.

/// What the field is showing.
public enum StripeMotion: Equatable, Sendable {
    /// The brand mark: a symmetric diamond with one authored break per column.
    case resting
    /// Live input. Levels are 0…1, oldest first. The newest level sits in the
    /// centre column and older levels ripple outward to both edges.
    case live([Float])
    /// A travelling wave for transcribing and polishing.
    case working
    /// Every column collapsed to its centre, like a quiet line.
    case quiet
    /// Quiet columns with the centre column drawn as an exclamation mark.
    case alert
}

/// Column and row occupancy for a stripe field. Row 0 is the top row.
public struct StripeField: Equatable, Sendable {
    public let columns: Int
    public let rows: Int

    /// `columns` is forced odd so the field has a centre column; `rows` is
    /// forced even so every column centres on the same line.
    public init(columns: Int, rows: Int) {
        let c = max(1, columns)
        self.columns = c % 2 == 0 ? c - 1 : c
        let r = max(2, rows)
        self.rows = r % 2 == 0 ? r : r + 1
    }

    /// Distance of `column` from the centre, 0 at the centre and 1 at the edges.
    public func distanceFromCentre(_ column: Int) -> Double {
        let centre = Double(columns - 1) / 2
        guard centre > 0 else { return 0 }
        return abs(Double(column) - centre) / centre
    }

    /// Column heights as fractions of the field height, 0…1.
    public func heights(for motion: StripeMotion, time: Double = 0) -> [Double] {
        (0..<columns).map { column in
            let d = distanceFromCentre(column)
            switch motion {
            case .resting:
                return 0.22 + 0.78 * pow(1 - d, 1.35)
            case .live(let levels):
                guard !levels.isEmpty else { return Self.floor }
                let level = Self.sample(levels, at: (1 - d) * Double(levels.count - 1))
                let envelope = 1 - 0.5 * d * d
                let shimmer = 0.9 + 0.1 * sin(time * 9 + Double(column) * 1.7)
                return min(1, max(Self.floor, level * envelope * shimmer))
            case .working:
                let envelope = 1 - 0.6 * d * d
                let wave = 0.5 + 0.5 * sin(time * 5 - Double(column) * 0.7)
                return 0.18 + 0.42 * envelope * wave
            case .quiet, .alert:
                return 0
            }
        }
    }

    /// Lit rows for every column.
    ///
    /// Live and working fields break at pseudo-random rows, more often near
    /// the tips. With `flicker` the break pattern changes six times a second;
    /// without it the pattern is fixed, which suits small or static glyphs and
    /// Reduce Motion.
    public func litRows(for motion: StripeMotion, time: Double = 0, flicker: Bool = true) -> [[Int]] {
        switch motion {
        case .resting:
            return heights(for: .resting).enumerated().map { column, height in
                restingRows(column: column, height: height)
            }
        case .quiet:
            return (0..<columns).map { _ in centredSpan(height: 0) }
        case .alert:
            // The columns beside the mark stay empty so it reads as "!"
            // rather than crossing the line.
            let centre = columns / 2
            return (0..<columns).map { column in
                switch abs(column - centre) {
                case 0: return exclamationRows()
                case 1: return []
                default: return centredSpan(height: 0)
                }
            }
        case .live, .working:
            let tick = flicker ? Int((time * 6).rounded(.down)) : 0
            return heights(for: motion, time: time).enumerated().map { column, height in
                brokenRows(column: column, height: height, tick: tick)
            }
        }
    }

    // MARK: - Rules

    /// Shortest a live column gets, so silence still reads as a line of dots.
    static let floor = 0.1

    /// Where each resting column breaks, as a fraction of its lit span.
    /// Alternating above and below centre gives the mark its rhythm.
    static let restingBreaks: [Double] = [0.72, 0.30, 0.70, 0.26, 0.66, 0.34, 0.74, 0.28, 0.68]

    /// Number of lit rows for a height, matched to the field's parity so the
    /// span centres exactly.
    func litCount(for height: Double) -> Int {
        var lit = min(rows, max(2, Int((height * Double(rows)).rounded())))
        if (rows - lit) % 2 != 0 { lit += lit < rows ? 1 : -1 }
        return lit
    }

    /// Rows lit by a column of `height`, centred vertically.
    func centredSpan(height: Double) -> [Int] {
        let lit = litCount(for: height)
        let top = (rows - lit) / 2
        return Array(top..<(top + lit))
    }

    func restingRows(column: Int, height: Double) -> [Int] {
        var span = centredSpan(height: height)
        guard span.count >= 6, let top = span.first else { return span }
        let fraction = Self.restingBreaks[column % Self.restingBreaks.count]
        let gap = top + Int((Double(span.count - 1) * fraction).rounded())
        span.removeAll { $0 == gap }
        return span
    }

    /// A stroke over the upper part of the column, a gap, then a dot.
    func exclamationRows() -> [Int] {
        let r = Double(rows)
        let strokeTop = Int((r * 0.08).rounded())
        let strokeEnd = max(strokeTop + 1, Int((r * 0.62).rounded()))
        let dotTop = min(rows - 1, max(strokeEnd + 1, Int((r * 0.76).rounded())))
        let dotEnd = min(rows, max(dotTop + 1, Int((r * 0.92).rounded())))
        return Array(strokeTop..<strokeEnd) + Array(dotTop..<dotEnd)
    }

    func brokenRows(column: Int, height: Double, tick: Int) -> [Int] {
        let span = centredSpan(height: height)
        guard span.count > 2 else { return span }
        let half = Double(span.count) / 2
        let middle = Double(rows) / 2
        return span.filter { row in
            let tip = abs(Double(row) + 0.5 - middle) / half  // 0 centre, 1 tip
            let chance = 0.06 + 0.34 * tip * tip * tip
            return StripeNoise.unit(column, row, tick) >= chance
        }
    }

    /// Linear interpolation into `levels` at a fractional index.
    static func sample(_ levels: [Float], at position: Double) -> Double {
        let clamped = min(Double(levels.count - 1), max(0, position))
        let lower = Int(clamped)
        let upper = min(levels.count - 1, lower + 1)
        let t = clamped - Double(lower)
        return Double(levels[lower]) * (1 - t) + Double(levels[upper]) * t
    }
}

/// Deterministic hash noise, 0 ≤ value < 1.
public enum StripeNoise {
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

// MARK: - Colour

/// An sRGB colour with components in 0…1.
public struct StripeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
    }
}

/// The dithered palette, sampled from stills of the design reference.
///
/// The reference never shows a whole rainbow at once: each moment has its own
/// small gradient, and the image drifts from one to the next. So the palette
/// is a list of scenes. A field shows one scene as a left-to-right gradient,
/// holds it, then dissolves cell by cell into the next.
public enum StripePalette {
    /// Scene gradients, each ordered left to right.
    public static let scenes: [[StripeColor]] = [
        // Sunrise: magenta and coral through orange and yellow to teal.
        [0xD04B8C, 0xDF5451, 0xEF6F21, 0xF8971C, 0xFCB018, 0x5EBC7E, 0x01CA93, 0x05CFA7],
        // Lagoon: cream and mint, a crimson band, dusty grey, turquoise.
        [0xF4EED8, 0xCFE3CC, 0xD9894C, 0xE1283F, 0xD62A5E, 0xB8638F, 0x9E9E9E, 0x5CC5BD],
        // Dusk: cream to turquoise and steel blue, violet, then crimson.
        [0xF5EFD8, 0xCDE5D3, 0x5CC4B8, 0x64A2C8, 0x9A5A9E, 0xD9306A, 0xDE2A5E],
        // Blush: peach and sand, dusty pink and mauve, crimson and red.
        [0xF9E4CF, 0xE8D8A0, 0xD8A0A8, 0xA89AA8, 0xA85A8E, 0xE01E50, 0xD8322E],
        // Ember: sand yellow and apricot into tangerine, red, and pink.
        [0xE8CF60, 0xE0A060, 0xE8683A, 0xE0302A, 0xE0204E, 0xD84C90, 0xC8B8A8],
    ].map { $0.map(StripeColor.init(hex:)) }

    /// Every scene's colours in one list. `index` returns positions in it,
    /// so renderers can batch cells by colour.
    public static let stops: [StripeColor] = scenes.flatMap { $0 }

    /// Seconds each scene lasts, including its dissolve into the next.
    public static let sceneSeconds = 5.0
    /// Seconds at the end of each scene spent dissolving into the next.
    public static let dissolveSeconds = 1.5

    private static let sceneOffsets: [Int] = scenes.indices.map { i in
        scenes[..<i].reduce(0) { $0 + $1.count }
    }

    /// The scene showing at `time`, the one after it, and how far the
    /// dissolve between them has run (0…1).
    public static func sceneBlend(at time: Double) -> (from: Int, to: Int, amount: Double) {
        let t = max(0, time.isFinite ? time : 0)
        let slot = (t / sceneSeconds).rounded(.down)
        let within = t - slot * sceneSeconds
        let from = Int(slot.truncatingRemainder(dividingBy: Double(scenes.count)))
        let hold = sceneSeconds - dissolveSeconds
        let amount = within <= hold ? 0 : min(1, (within - hold) / dissolveSeconds)
        return (from, (from + 1) % scenes.count, amount)
    }

    /// Index into `stops` for one cell at `time`.
    ///
    /// Time 0 is the first scene with no drift, which is how still marks
    /// (brand mark, app icon) are coloured. The gradient runs mostly left to
    /// right with a slight vertical lean and sways gently while animating.
    /// Between two neighbouring colours a 4×4 ordered dither picks one per
    /// cell; during a dissolve, per-cell noise picks the old or new scene.
    public static func index(column: Int, row: Int, columns: Int, rows: Int, time: Double = 0) -> Int {
        let blend = sceneBlend(at: time)
        let scene = StripeNoise.unit(column, row, 7) < blend.amount ? blend.to : blend.from
        let colours = scenes[scene]
        let x = Double(column) / Double(max(1, columns - 1))
        let y = Double(row) / Double(max(1, rows - 1))
        let sway = time == 0 ? 0 : 0.06 * sin(time * 0.9)
        let g = min(1, max(0, x * 0.8 + y * 0.2 + sway))
        let scaled = g * Double(colours.count - 1)
        let lower = min(colours.count - 2, Int(scaled))
        let fraction = scaled - Double(lower)
        let pick = fraction > OrderedDither.threshold(column: column, row: row) ? lower + 1 : lower
        return sceneOffsets[scene] + pick
    }
}

/// Bayer 4×4 ordered dithering.
public enum OrderedDither {
    static let bayer4: [Int] = [
        0, 8, 2, 10,
        12, 4, 14, 6,
        3, 11, 1, 9,
        15, 7, 13, 5,
    ]

    /// Threshold for a cell, strictly between 0 and 1.
    public static func threshold(column: Int, row: Int) -> Double {
        let c = ((column % 4) + 4) % 4
        let r = ((row % 4) + 4) % 4
        return (Double(bayer4[r * 4 + c]) + 0.5) / 16
    }
}

// MARK: - Layout

/// Where a field's cells land inside a rectangle, in points.
public struct StripeLayout: Equatable, Sendable {
    public let field: StripeField
    public let bar: Double
    public let pitch: Double
    public let cell: Double
    public let originX: Double
    public let originY: Double

    /// Fixed bar, gap, and cell sizes; as many columns and rows as fit,
    /// centred on whole points so integer metrics stay pixel sharp.
    public static func fitted(width: Double, height: Double,
                              bar: Double, gap: Double, cell: Double) -> StripeLayout {
        let pitch = bar + gap
        let field = StripeField(columns: Int((width + gap) / pitch),
                                rows: Int(height / cell))
        let usedWidth = Double(field.columns) * pitch - gap
        let usedHeight = Double(field.rows) * cell
        return StripeLayout(field: field, bar: bar, pitch: pitch, cell: cell,
                            originX: ((width - usedWidth) / 2).rounded(.down),
                            originY: ((height - usedHeight) / 2).rounded(.down))
    }

    /// A fixed column and row count scaled to fill the rectangle. Bars take
    /// 60% of each column's pitch. Used for the brand mark at any size.
    public static func proportional(width: Double, height: Double,
                                    columns: Int, rows: Int) -> StripeLayout {
        let field = StripeField(columns: columns, rows: rows)
        let pitch = width / (Double(field.columns) - 0.4)
        let bar = pitch * 0.6
        let cell = height / Double(field.rows)
        let usedWidth = Double(field.columns - 1) * pitch + bar
        return StripeLayout(field: field, bar: bar, pitch: pitch, cell: cell,
                            originX: (width - usedWidth) / 2, originY: 0)
    }

    /// Rectangle of one cell: x, y, width, height.
    public func rect(column: Int, row: Int) -> (x: Double, y: Double, width: Double, height: Double) {
        (originX + Double(column) * pitch, originY + Double(row) * cell, bar, cell)
    }
}

// MARK: - Appearance

/// How active stripes are inked. Chosen in Settings → General.
public enum StripeStyle: String, CaseIterable, Sendable {
    /// Dithered palette on a dark surface.
    case color
    /// White stripes on a dark surface.
    case whiteOnBlack
    /// Black stripes on a light surface.
    case blackOnWhite

    public static let defaultsKey = "murmur.stripeStyle"

    public var title: String {
        switch self {
        case .color: "Color"
        case .whiteOnBlack: "White on black"
        case .blackOnWhite: "Black on white"
        }
    }

    public var usesPalette: Bool { self == .color }
    public var hasDarkSurface: Bool { self != .blackOnWhite }
}
