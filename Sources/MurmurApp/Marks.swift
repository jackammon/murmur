import AppKit
import SwiftUI
import MurmurDesign

// Renderers for Murmur's two marks, defined in MurmurDesign:
//
// - The round-stipple dot wave (`DotWave`) for the listening HUD and the
//   popover's live wave.
// - The Lean mark (`LeanMarkShape`, `MurmurMark`, `StatusGlyph`) for the
//   menu bar, popover header, About and onboarding.
//
// Pills are drawn as a straight stroke with round caps, so a pill of length
// L and thickness t is a segment of length L − t along the pill's axis.

// MARK: - Dot wave

/// What the dot wave shows.
enum DotWaveMotion: Equatable {
    /// Live input: 0…1 levels, oldest first.
    case live([Float])
    /// A slow travelling swell, for transcribing and polishing.
    case working
    /// A single dotted line.
    case quiet
    /// An exclamation mark, for errors.
    case alert
    /// A paste animation that started at `start`, gathering from `heights`.
    case paste(PasteAnimation, start: Date, heights: [Double])
}

/// Round-stipple dots sized to the view's frame. Only lit dots are drawn.
///
/// Live heights glide towards each new level instead of stepping. Uses
/// `TimelineView` + `Canvas` at up to 30 fps, paused for still states and
/// Reduce Motion.
struct DotWave: View {
    var motion: DotWaveMotion
    var grid: DotGrid = .hud
    var dotSize: CGFloat = 1.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var smoother = HeightSmoother()

    private var animates: Bool {
        switch motion {
        case .live, .working, .paste: return !reduceMotion
        case .quiet, .alert: return false
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { timeline in
            Canvas { context, size in
                let dots = litDots(at: timeline.date)
                guard !dots.isEmpty else { return }
                let d = min(dotSize, size.height / CGFloat(grid.rows))
                let pitchX = grid.columns > 1 ? (size.width - d) / CGFloat(grid.columns - 1) : 0
                let pitchY = grid.rows > 1 ? (size.height - d) / CGFloat(grid.rows - 1) : 0
                var path = Path()
                for dot in dots {
                    path.addEllipse(in: CGRect(x: CGFloat(dot.column) * pitchX,
                                               y: CGFloat(dot.row) * pitchY,
                                               width: d, height: d))
                }
                context.fill(path, with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }

    private func litDots(at date: Date) -> Set<Dot> {
        switch motion {
        case .live(let levels):
            let target = grid.liveHeights(levels: levels)
            let heights = reduceMotion ? target : smoother.step(towards: target, at: date)
            return grid.lit(heights: heights)
        case .working:
            let time = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
            return grid.lit(heights: grid.workingHeights(time: time))
        case .quiet:
            return grid.quietLine
        case .alert:
            return grid.alert
        case .paste(let animation, let start, let heights):
            if reduceMotion { return grid.lit(heights: heights) }
            let progress = date.timeIntervalSince(start) / PasteAnimation.duration
            return animation.lit(in: grid, progress: min(1, max(0, progress)), from: heights)
        }
    }
}

/// Eases displayed heights towards their targets between audio updates.
/// A reference type so the Canvas can advance it frame to frame.
final class HeightSmoother {
    private var current: [Double] = []
    private var last: Date?

    func step(towards target: [Double], at date: Date) -> [Double] {
        let dt = last.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        guard current.count == target.count else { current = target; return target }
        let k = 1 - exp(-dt * 12)
        current = zip(current, target).map { $0 + ($1 - $0) * k }
        return current
    }
}

// MARK: - Lean mark

/// The Lean mark as a SwiftUI shape, scaled to fit its frame. Fill it with
/// any style; the pills are stroked capsules built into the path.
struct LeanMarkShape: Shape {
    var pills: [LeanMark.Pill] = LeanMark.pills
    /// Stroke on the 16 × 14 box; use `LeanMark.menuBarThickness` at 16 pt.
    var thickness: Double = LeanMark.thickness

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width / LeanMark.width, rect.height / LeanMark.height)
        let origin = CGPoint(x: rect.midX - LeanMark.width * k / 2, y: rect.midY - LeanMark.height * k / 2)
        var path = Path()
        for segment in LeanGeometry.segments(pills, thickness: thickness) {
            var line = Path()
            line.move(to: CGPoint(x: origin.x + segment.a.x * k, y: origin.y + segment.a.y * k))
            line.addLine(to: CGPoint(x: origin.x + segment.b.x * k, y: origin.y + segment.b.y * k))
            path.addPath(line.strokedPath(StrokeStyle(lineWidth: thickness * k, lineCap: .round)))
        }
        return path
    }
}

/// Pill end points on the 16 × 14 box, y down.
enum LeanGeometry {
    struct Segment { let a: CGPoint; let b: CGPoint }

    static func segments(_ pills: [LeanMark.Pill], thickness: Double = LeanMark.thickness) -> [Segment] {
        let angle = LeanMark.tilt * .pi / 180
        let dx = cos(angle), dy = sin(angle)
        return pills.map { pill in
            let half = max(0, pill.length - thickness) / 2
            return Segment(a: CGPoint(x: pill.centreX - dx * half, y: pill.centreY - dy * half),
                           b: CGPoint(x: pill.centreX + dx * half, y: pill.centreY + dy * half))
        }
    }

    /// An exclamation mark in the same tilted pills, for the error state.
    static let alert: [LeanMark.Pill] = {
        let angle = LeanMark.tilt * .pi / 180
        let stroke = LeanMark.Pill(centreX: 7.4, centreY: 5.2, length: 9.5)
        let reach = stroke.length / 2 + 2.6
        let dot = LeanMark.Pill(centreX: stroke.centreX + cos(angle) * reach,
                                centreY: stroke.centreY + sin(angle) * reach,
                                length: LeanMark.thickness)
        return [stroke, dot]
    }()
}

/// The brand mark for About and onboarding: the Lean mark on a Paper tile,
/// matching the app icon.
struct MurmurMark: View {
    var size: CGFloat

    static let paper = Color(red: 0.969, green: 0.961, blue: 0.945)  // #F7F5F1
    static let ink = Color(red: 0.090, green: 0.078, blue: 0.059)    // #17140F

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Self.paper)
                .shadow(color: .black.opacity(0.14), radius: size * 0.05, y: size * 0.025)
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
            LeanMarkShape()
                .fill(Self.ink)
                .frame(width: size * 0.56, height: size * 0.56 * LeanMark.height / LeanMark.width)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Murmur")
    }
}

// MARK: - Menu bar

/// Template images for the status item: the Lean mark at 16 × 14 pt.
enum StatusGlyph {
    enum Kind: Equatable {
        /// The mark at rest.
        case rest
        /// Pill lengths follow the microphone.
        case listening([Float])
        /// The mark, dimmed: loading or transcribing.
        case dimmed
        /// A tilted exclamation mark.
        case alert
    }

    private static let badgeWidth: CGFloat = 4

    /// - Parameter badge: adds a small dot at the top right, e.g. an update is ready.
    static func image(_ kind: Kind, badge: Bool = false) -> NSImage {
        let size = NSSize(width: LeanMark.width + (badge ? badgeWidth : 0), height: LeanMark.height)
        let pills: [LeanMark.Pill]
        switch kind {
        case .rest, .dimmed: pills = LeanMark.pills
        case .listening(let levels): pills = LeanMark.pills(levels: levels)
        case .alert: pills = LeanGeometry.alert
        }
        let alpha: CGFloat = kind == .dimmed ? 0.45 : 1
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.withAlphaComponent(alpha).setStroke()
            for segment in LeanGeometry.segments(pills, thickness: LeanMark.menuBarThickness) {
                let path = NSBezierPath()
                path.move(to: segment.a)
                path.line(to: segment.b)
                path.lineWidth = LeanMark.menuBarThickness
                path.lineCapStyle = .round
                path.stroke()
            }
            if badge {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: size.width - 3.5, y: 0.5, width: 3.5, height: 3.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
