import Foundation

/// Murmur's logo: four tilted pills, like quick handwriting. The same
/// geometry draws the menu-bar icon, the popover header, the About and
/// onboarding mark, and the app icon (`scripts/icon/main.swift`).
public enum LeanMark {
    /// A rounded bar, described by its centre and length on the mark's box.
    /// Every pill has the same thickness and tilt.
    public struct Pill: Equatable, Sendable {
        public let centreX: Double
        public let centreY: Double
        public let length: Double

        public init(centreX: Double, centreY: Double, length: Double) {
            self.centreX = centreX
            self.centreY = centreY
            self.length = length
        }
    }

    /// The mark is drawn on a 16 × 14 pt box: its menu-bar size.
    public static let width: Double = 16
    public static let height: Double = 14
    /// Pill thickness at menu-bar size.
    public static let thickness: Double = 2
    /// Angle of every pill, in degrees from horizontal.
    public static let tilt: Double = 70

    public static let pills: [Pill] = [
        Pill(centreX: 3, centreY: 8.5, length: 7),
        Pill(centreX: 7, centreY: 7, length: 12),
        Pill(centreX: 11, centreY: 7.5, length: 9),
        Pill(centreX: 14.2, centreY: 8.8, length: 5),
    ]

    /// The pills while listening: each keeps its place and tilt, and its
    /// length follows the microphone, newest level on the left pill.
    /// `levels` are 0…1, oldest first.
    public static func pills(levels: [Float]) -> [Pill] {
        guard let newest = levels.indices.last else { return pills }
        return pills.enumerated().map { index, pill in
            let level = Double(levels[max(0, newest - index * 2)])
            let scale = 0.35 + 0.65 * min(1, max(0, level))
            return Pill(centreX: pill.centreX, centreY: pill.centreY,
                        length: max(thickness, pill.length * scale))
        }
    }

    /// Axis-aligned bounds of a pill once tilted, as (minX, minY, maxX, maxY).
    public static func bounds(of pill: Pill, thickness: Double = thickness) -> (Double, Double, Double, Double) {
        let a = tilt * .pi / 180
        let halfW = (abs(cos(a)) * pill.length + abs(sin(a)) * thickness) / 2
        let halfH = (abs(sin(a)) * pill.length + abs(cos(a)) * thickness) / 2
        return (pill.centreX - halfW, pill.centreY - halfH, pill.centreX + halfW, pill.centreY + halfH)
    }
}
