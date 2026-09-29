import AppKit
import SwiftUI
import MurmurDesign

// Renderers for the stripe field defined in MurmurDesign. `StripeWave` draws
// it in SwiftUI (popover, overlay, brand mark); `StatusGlyph` draws it into
// template images for the menu bar.

// MARK: - SwiftUI

/// How a `StripeWave` is coloured.
enum StripeInk: Equatable {
    /// The dithered palette.
    case palette
    /// The view's foreground style, e.g. `.primary`.
    case foreground
    /// One fixed colour.
    case solid(Color)
}

/// Fixed metrics for a `StripeWave`. Integer values stay pixel sharp.
struct StripeMetrics: Equatable {
    var bar: CGFloat
    var gap: CGFloat
    var cell: CGFloat

    /// Overlay HUD and popover header.
    static let regular = StripeMetrics(bar: 2, gap: 2, cell: 2)
    /// Tight header glyph, the same density as the menu-bar icon.
    static let compact = StripeMetrics(bar: 2, gap: 1, cell: 1)
}

/// An animated stripe field sized to its frame.
///
/// Uses `TimelineView` + `Canvas`, capped at 30 fps and paused when
/// `animated` is false or Reduce Motion is on, so a resting mark costs one draw.
struct StripeWave: View {
    var motion: StripeMotion
    var ink: StripeInk = .foreground
    var metrics: StripeMetrics = .regular
    /// When set (0…1), columns past this fraction are drawn dim. Used for
    /// transcription progress.
    var progress: Double? = nil
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAnimating: Bool {
        guard animated, !reduceMotion else { return false }
        switch motion {
        case .live, .working: return true
        case .resting, .quiet, .alert: return false
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            Canvas { context, size in
                let layout = StripeLayout.fitted(
                    width: size.width, height: size.height,
                    bar: metrics.bar, gap: metrics.gap, cell: metrics.cell
                )
                let time = isAnimating ? timeline.date.timeIntervalSinceReferenceDate : 0
                StripePainter.paint(layout: layout, motion: motion, time: time,
                                    flicker: isAnimating, ink: ink,
                                    progress: progress, in: &context)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The brand mark: the resting stripe field on a rounded tile, like the app
/// icon. Follows the Settings stripe style.
struct MurmurMark: View {
    var size: CGFloat
    @AppStorage(StripeStyle.defaultsKey) private var style: StripeStyle = .color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(style.hasDarkSurface ? Color(white: 0.09) : Color(white: 0.97))
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            Canvas { context, canvasSize in
                let layout = StripeLayout.proportional(
                    width: canvasSize.width, height: canvasSize.height,
                    columns: 9, rows: 22
                )
                StripePainter.paint(layout: layout, motion: .resting, time: 0, flicker: false,
                                    ink: style.usesPalette ? .palette
                                        : .solid(style.hasDarkSurface ? .white : .black),
                                    progress: nil, in: &context)
            }
            .frame(width: size * 0.62, height: size * 0.56)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Murmur")
    }
}

enum StripePainter {
    /// Fills every lit cell, batching cells that share a colour into one path.
    static func paint(layout: StripeLayout, motion: StripeMotion, time: Double, flicker: Bool,
                      ink: StripeInk, progress: Double?, in context: inout GraphicsContext) {
        let field = layout.field
        let lit = field.litRows(for: motion, time: time, flicker: flicker)
        let stops = StripePalette.stops
        var palettePaths = [Path](repeating: Path(), count: stops.count)
        var solidPath = Path()
        var dimPath = Path()

        for (column, rows) in lit.enumerated() {
            let fraction = Double(column + 1) / Double(field.columns)
            let dim = progress.map { fraction > $0 + 0.0001 } ?? false
            for row in rows {
                let r = layout.rect(column: column, row: row)
                let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
                if dim {
                    dimPath.addRect(rect)
                } else if case .palette = ink {
                    let index = StripePalette.index(column: column, row: row,
                                                    columns: field.columns, rows: field.rows,
                                                    time: time)
                    palettePaths[index].addRect(rect)
                } else {
                    solidPath.addRect(rect)
                }
            }
        }

        for (index, path) in palettePaths.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(Color(stops[index])))
        }
        switch ink {
        case .palette: break
        case .foreground: context.fill(solidPath, with: .foreground)
        case .solid(let color): context.fill(solidPath, with: .color(color))
        }
        if !dimPath.isEmpty {
            context.opacity = 0.28
            context.fill(dimPath, with: .foreground)
        }
    }
}

extension Color {
    init(_ stripe: StripeColor) {
        self.init(.sRGB, red: stripe.red, green: stripe.green, blue: stripe.blue, opacity: 1)
    }
}

// MARK: - Menu bar

/// Template images for the status item, drawn from the same stripe field as
/// the rest of the app: 7 columns of 2 pt bars with 1 pt gaps and 1 pt rows.
enum StatusGlyph {
    static let fieldSize = NSSize(width: 20, height: 16)
    private static let metrics = (bar: 2.0, gap: 1.0, cell: 1.0)
    private static let badgeWidth: CGFloat = 4

    /// - Parameters:
    ///   - dimmed: draws at reduced opacity, e.g. while the model loads.
    ///   - badge: adds a small dot at the top right, e.g. an update is ready.
    static func image(for motion: StripeMotion, dimmed: Bool = false, badge: Bool = false) -> NSImage {
        let size = NSSize(width: fieldSize.width + (badge ? badgeWidth : 0), height: fieldSize.height)
        let layout = StripeLayout.fitted(width: fieldSize.width, height: fieldSize.height,
                                         bar: metrics.bar, gap: metrics.gap, cell: metrics.cell)
        // Menu-bar breaks never flicker: at this size it reads as noise.
        let lit = layout.field.litRows(for: motion, time: 0, flicker: false)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.withAlphaComponent(dimmed ? 0.45 : 1).setFill()
            for (column, rows) in lit.enumerated() {
                for row in rows {
                    let r = layout.rect(column: column, row: row)
                    NSRect(x: r.x, y: r.y, width: r.width, height: r.height).fill()
                }
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
