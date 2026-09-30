import Foundation

// Optional colour themes: the reference GIF's colours behind the listening
// HUD, the About mark and the Dock icon. The menu bar stays monochrome.
//
// Every theme keeps colour in large, calm areas and dithers only where two
// colours meet, with a scrim or dark ink wherever the dots need contrast.
// This file decides the colour of each cell; renderers draw the cells.

/// An sRGB colour, components 0…1.
public struct RGB: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
    }

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = RGB(red: 0, green: 0, blue: 0)
    public static let paperWhite = RGB(red: 1, green: 252 / 255, blue: 248 / 255)
}

/// A colour laid over the whole field at some opacity.
public struct Tint: Equatable, Sendable {
    public let colour: RGB
    public let opacity: Double
}

/// How a theme lays its colours out.
public struct ColourField: Equatable, Sendable {
    public enum Layout: Equatable, Sendable {
        /// Soft areas around a few points, like a still from the GIF.
        case field(seed: Double)
        /// The field, moving through all five stills while you speak.
        case everyStill(seed: Double)
        /// Horizontal bands with a gentle wave.
        case bands
        /// Diagonal bands.
        case slant
        /// Two colours meeting at one wavy edge.
        case duo
    }

    public let layout: Layout
    public let palette: [RGB]
    /// Laid over the colours so the dots and text read.
    public let scrim: Tint?
    /// True when dots, text and the mark are drawn light on this field.
    public let lightInk: Bool
    /// When set, colour shows only as a thin rim; the rest of the surface is this.
    public let rim: Tint?
    /// Dither cell size in points on the HUD.
    public let cellSize: Double

    /// A soft shadow under light dots and text, for fields with bright areas.
    public var halo: Bool { lightInk && rim == nil }

    /// The colour of one cell.
    ///
    /// - Parameters:
    ///   - u, v: the cell's centre, 0…1 across and down the surface.
    ///   - aspect: height ÷ width, so areas stay round on wide surfaces.
    ///   - column, row: the cell's index, for the ordered dither.
    ///   - time: seconds; the colours drift as it advances.
    public func colour(u: Double, v: Double, aspect: Double, column: Int, row: Int, time t: Double) -> RGB {
        switch layout {
        case .field(let seed):
            return Self.nearest(palette, seed: seed, u: u, v: v, aspect: aspect, column: column, row: row, time: t)
        case .everyStill(let seed):
            let slot = Int((max(0, t) / Self.stillSeconds).rounded(.down))
            let within = max(0, t) - Double(slot) * Self.stillSeconds
            let dissolve = clamp((within - (Self.stillSeconds - 1.2)) / 1.2)
            let index = DotNoise.unit(column, row, 11) < dissolve ? slot + 1 : slot
            let still = ColourTheme.stills[index % ColourTheme.stills.count]
            return Self.nearest(still, seed: seed, u: u, v: v, aspect: aspect, column: column, row: row, time: t)
        case .bands:
            let wave = 0.08 * sin(u * 3.4 + t * 0.35) + 0.04 * sin(u * 7 - t * 0.2)
            return Self.band(palette, at: v + wave, column: column, row: row)
        case .slant:
            return Self.band(palette, at: (u * 0.7 + v * 0.6) * 0.8 + 0.05 * sin(t * 0.3 + v * 4),
                             column: column, row: row)
        case .duo:
            let edge = 0.5 + 0.14 * sin(v * 4.5 + t * 0.4) - u
            return smooth(-0.07, 0.07, edge) > Bayer.threshold(column: column, row: row) ? palette[0] : palette[1]
        }
    }

    /// Seconds each still holds in `everyStill`, including its dissolve.
    public static let stillSeconds: Double = 6

    /// Nearest of a few drifting points; dithered only in a narrow seam.
    static func nearest(_ palette: [RGB], seed: Double, u: Double, v: Double, aspect: Double,
                        column: Int, row: Int, time t: Double) -> RGB {
        let vv = 0.5 + (v - 0.5) * max(aspect, 0.35)
        var first = 0, second = 0
        var d1 = Double.infinity, d2 = Double.infinity
        for i in palette.indices {
            let fi = Double(i)
            let x = 0.5 + 0.42 * sin(seed * 1.3 + fi * 2.1) + 0.06 * sin(t * 0.35 + fi * 1.7)
            let y = 0.5 + 0.42 * cos(seed * 0.7 + fi * 1.9) + 0.06 * cos(t * 0.3 + fi * 2.3)
            let d = hypot(u - x, vv - y)
            if d < d1 { d2 = d1; second = first; d1 = d; first = i }
            else if d < d2 { d2 = d; second = i }
        }
        let seam = 1 - smooth(0, 0.1, d2 - d1)
        return seam * 0.5 > Bayer.threshold(column: column, row: row) ? palette[second] : palette[first]
    }

    /// A position 0…1 through `palette`, dithered between neighbours.
    static func band(_ palette: [RGB], at position: Double, column: Int, row: Int) -> RGB {
        let s = min(0.9999, max(0, position)) * Double(palette.count - 1)
        let k = min(palette.count - 2, Int(s))
        let f = s - Double(k)
        return smooth(0.35, 0.65, f) > Bayer.threshold(column: column, row: row) ? palette[k + 1] : palette[k]
    }
}

/// The Colour setting. Off by default.
public enum ColourTheme: String, CaseIterable, Sendable {
    case off
    // Field
    case sunrise, lagoon, dusk, ember, everyStill
    // Wash
    case blushWash, dawn, lagoonWash
    // Horizon
    case sunriseHorizon, duskHorizon, blushHorizon, emberSlant
    // Duotone
    case citrus, tide
    // Rim and grain
    case sunriseRim, duskRim, bigPixel, fineGrain

    public static let defaultsKey = "murmur.colourTheme"

    public var title: String {
        switch self {
        case .off: "Off"
        case .sunrise: "Sunrise"
        case .lagoon: "Lagoon"
        case .dusk: "Dusk"
        case .ember: "Ember"
        case .everyStill: "Every still"
        case .blushWash: "Blush wash"
        case .dawn: "Dawn"
        case .lagoonWash: "Lagoon wash"
        case .sunriseHorizon: "Sunrise horizon"
        case .duskHorizon: "Dusk horizon"
        case .blushHorizon: "Blush horizon"
        case .emberSlant: "Ember slant"
        case .citrus: "Citrus"
        case .tide: "Tide"
        case .sunriseRim: "Sunrise rim"
        case .duskRim: "Dusk rim"
        case .bigPixel: "Big pixel"
        case .fineGrain: "Fine grain"
        }
    }

    /// A named section of the Colour menu.
    public struct Group: Sendable {
        public let title: String
        public let themes: [ColourTheme]
    }

    /// Settings groups, in menu order.
    public static let groups: [Group] = [
        Group(title: "Field", themes: [.sunrise, .lagoon, .dusk, .ember, .everyStill]),
        Group(title: "Wash", themes: [.blushWash, .dawn, .lagoonWash]),
        Group(title: "Horizon", themes: [.sunriseHorizon, .duskHorizon, .blushHorizon, .emberSlant]),
        Group(title: "Duotone", themes: [.citrus, .tide]),
        Group(title: "Rim and grain", themes: [.sunriseRim, .duskRim, .bigPixel, .fineGrain]),
    ]

    // Palettes sampled from the reference stills.
    static let sunrisePalette = hexes(0xFCB018, 0xEF6F21, 0x01CA93, 0xD74351)
    static let lagoonPalette = hexes(0xF4EED8, 0x5CC5BD, 0xD62A5E, 0xCFE3CC)
    static let duskPalette = hexes(0xF5EFD8, 0x64A2C8, 0x9A5A9E, 0xDE2A5E)
    static let blushPalette = hexes(0xF9E4CF, 0xD8A0A8, 0xE01E50, 0xE8D8A0)
    static let emberPalette = hexes(0xE8CF60, 0xE8683A, 0xE0302A, 0xD84C90)
    static let dawnPalette = hexes(0xF2C9A8, 0xEDC154, 0xD8A0A8, 0xCDE5D3)

    /// The five stills `everyStill` moves through.
    static let stills = [sunrisePalette, lagoonPalette, duskPalette, blushPalette, emberPalette]

    private static func hexes(_ values: UInt32...) -> [RGB] { values.map(RGB.init(hex:)) }
    private static func dim(_ opacity: Double) -> Tint { Tint(colour: .black, opacity: opacity) }
    private static func wash(_ opacity: Double) -> Tint { Tint(colour: .paperWhite, opacity: opacity) }

    /// The theme's field, or nil when colour is off.
    public var field: ColourField? {
        func make(_ layout: ColourField.Layout, _ palette: [RGB], scrim: Tint? = nil,
                  light: Bool, rim: Tint? = nil, cell: Double = 3) -> ColourField {
            ColourField(layout: layout, palette: palette, scrim: scrim, lightInk: light, rim: rim, cellSize: cell)
        }
        switch self {
        case .off: return nil
        case .sunrise: return make(.field(seed: 1), Self.sunrisePalette, scrim: Self.dim(0.28), light: true)
        case .lagoon: return make(.field(seed: 4), Self.lagoonPalette, scrim: Self.dim(0.4), light: true)
        case .dusk: return make(.field(seed: 7), Self.duskPalette, scrim: Self.dim(0.34), light: true)
        case .ember: return make(.field(seed: 2), Self.emberPalette, scrim: Self.dim(0.26), light: true)
        case .everyStill: return make(.everyStill(seed: 3), Self.sunrisePalette, scrim: Self.dim(0.3), light: true)
        case .blushWash: return make(.field(seed: 5), Self.blushPalette, scrim: Self.wash(0.42), light: false)
        case .dawn: return make(.field(seed: 8), Self.dawnPalette, scrim: Self.wash(0.2), light: false)
        case .lagoonWash: return make(.field(seed: 6), Self.lagoonPalette, scrim: Self.wash(0.35), light: false)
        case .sunriseHorizon: return make(.bands, Self.hexes(0xFCB018, 0xEF6F21, 0xD74351), light: false)
        case .duskHorizon: return make(.bands, Self.hexes(0xF5EFD8, 0x64A2C8, 0x9A5A9E), scrim: Self.wash(0.25), light: false)
        case .blushHorizon: return make(.bands, Self.hexes(0xF9E4CF, 0xD8A0A8, 0xE01E50), light: false)
        case .emberSlant: return make(.slant, Self.hexes(0xE8CF60, 0xE8683A, 0xE0302A), light: false)
        case .citrus: return make(.duo, Self.hexes(0xFCB018, 0xF8971C), light: false)
        case .tide: return make(.duo, Self.hexes(0x5CC4B8, 0x64A2C8), light: true)
        case .sunriseRim:
            return make(.field(seed: 1), Self.sunrisePalette, light: true,
                        rim: Tint(colour: RGB(hex: 0x161514), opacity: 0.92))
        case .duskRim:
            return make(.field(seed: 7), Self.duskPalette, light: false,
                        rim: Tint(colour: RGB(hex: 0xFCFBF9), opacity: 0.95))
        case .bigPixel: return make(.field(seed: 9), Self.sunrisePalette, scrim: Self.dim(0.22), light: true, cell: 6)
        case .fineGrain: return make(.field(seed: 4), Self.lagoonPalette, scrim: Self.dim(0.38), light: true, cell: 1.5)
        }
    }
}

/// Bayer 4 × 4 ordered-dither thresholds, strictly between 0 and 1.
public enum Bayer {
    static let matrix: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    public static func threshold(column: Int, row: Int) -> Double {
        let c = ((column % 4) + 4) % 4, r = ((row % 4) + 4) % 4
        return (Double(matrix[r * 4 + c]) + 0.5) / 16
    }
}

func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}
