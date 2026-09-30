import AppKit
import SwiftUI
import MurmurDesign

// Renderers for the optional colour themes (MurmurDesign/ColourTheme.swift):
// the field behind the listening HUD, the themed brand mark, and the Dock icon.

/// Colour field sized to its frame. Drifts only while `moving`; otherwise
/// it holds where it stopped. Redraws at up to 12 fps.
struct ColourFieldView: View {
    let field: ColourField
    var moving: Bool = false
    /// Dither cell size in points; defaults to the theme's HUD cell size.
    var cellSize: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = FieldClock()

    var body: some View {
        let animates = moving && !reduceMotion
        Group {
            if animates {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                    canvas(at: timeline.date, advancing: true)
                }
            } else {
                // A plain Canvas when still, so ImageRenderer (Dock icon) can draw it.
                canvas(at: Date(), advancing: false)
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(at date: Date, advancing: Bool) -> some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let time = clock.time(at: date, advancing: advancing)
            let cell = max(1, cellSize ?? CGFloat(field.cellSize))
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            let aspect = Double(size.height / size.width)
            var paths: [RGB: Path] = [:]
            for row in 0..<rows {
                for column in 0..<columns {
                    let colour = field.colour(u: (Double(column) + 0.5) / Double(columns),
                                              v: (Double(row) + 0.5) / Double(rows),
                                              aspect: aspect, column: column, row: row, time: time)
                    paths[colour, default: Path()].addRect(
                        CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            for (colour, path) in paths { context.fill(path, with: .color(Color(colour))) }
            if let scrim = field.scrim {
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(Color(scrim.colour).opacity(scrim.opacity)))
            }
        }
    }
}

/// Field time that advances only while the field is moving.
final class FieldClock {
    private var time: Double = 2
    private var last: Date?

    func time(at date: Date, advancing: Bool) -> Double {
        if advancing, let last { time += min(0.1, max(0, date.timeIntervalSince(last))) * 0.9 }
        last = date
        return time
    }
}

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// A surface filled with a theme: the field, or for rim themes a thin edge
/// of the field around a flat centre.
struct ColourSurface<S: InsettableShape>: View {
    let field: ColourField
    let shape: S
    var moving: Bool = false
    var cellSize: CGFloat? = nil
    var rimWidth: CGFloat = 2.2

    var body: some View {
        ZStack {
            ColourFieldView(field: field, moving: moving, cellSize: cellSize)
            if let rim = field.rim {
                shape.inset(by: rimWidth).fill(Color(rim.colour).opacity(rim.opacity))
            }
        }
        .clipShape(shape)
    }
}

/// The app icon drawn with a colour theme: the Lean mark on the themed tile.
/// Used for the Dock while Murmur runs and for the About/onboarding mark.
struct ThemedIconTile: View {
    let field: ColourField
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            ColourSurface(field: field, shape: shape, cellSize: max(1, size / 30), rimWidth: max(1.5, size * 0.06))
            shape.strokeBorder(Color.black.opacity(0.12), lineWidth: max(0.5, size / 400))
            LeanMarkShape()
                .fill(field.lightInk ? Color.white : MurmurMark.ink)
                .shadow(color: .black.opacity(field.lightInk ? 0.25 : 0), radius: size / 60)
                .frame(width: size * 0.56, height: size * 0.56 * LeanMark.height / LeanMark.width)
        }
        .frame(width: size, height: size)
    }
}

/// Swaps the Dock icon to match the colour theme while Murmur runs. Finder
/// and Launchpad keep the Paper icon from the app bundle; Off restores it.
@MainActor
enum DockIcon {
    static func apply(_ theme: ColourTheme) {
        guard let field = theme.field else {
            NSApp.applicationIconImage = nil
            return
        }
        // macOS icon grid: an 824 pt tile centred on a 1024 pt canvas.
        let icon = ThemedIconTile(field: field, size: 824)
            .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        if let image = renderer.nsImage {
            NSApp.applicationIconImage = image
        }
    }

    nonisolated static var current: ColourTheme {
        ColourTheme(rawValue: UserDefaults.standard.string(forKey: ColourTheme.defaultsKey) ?? "") ?? .off
    }
}
