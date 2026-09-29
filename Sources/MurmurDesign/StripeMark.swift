import Foundation

/// The brand mark — the resting stripe field in the first palette scene —
/// as a flat list of coloured cells. Shared by the in-app mark and the app
/// icon generator (`scripts/icon/main.swift`).
public enum StripeMark {
    public struct Cell: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
        public let color: StripeColor
    }

    /// Grid for a mark drawn `width` points wide. Small renders use a coarser
    /// grid so each bar and break stays at least a pixel or two wide.
    public static func grid(forWidth width: Double) -> (columns: Int, rows: Int) {
        switch width {
        case ..<12: return (5, 8)
        case ..<24: return (7, 12)
        default:    return (9, 22)
        }
    }

    /// Share of an icon tile's inner square the mark occupies. Small icons
    /// draw the mark larger so the bars survive the downscale.
    public static func scale(forTileSide side: Double) -> (width: Double, height: Double) {
        side < 48 ? (0.84, 0.7) : (0.62, 0.56)
    }

    /// Cells filling `width` × `height`, origin top left.
    ///
    /// - Parameter snap: rounds every edge to whole units, for pixel renders
    ///   at small sizes.
    public static func cells(width: Double, height: Double, snap: Bool = false) -> [Cell] {
        let grid = grid(forWidth: width)
        let layout = StripeLayout.proportional(width: width, height: height,
                                               columns: grid.columns, rows: grid.rows)
        let field = layout.field
        var cells: [Cell] = []
        for (column, rows) in field.litRows(for: .resting).enumerated() {
            for row in rows {
                var r = layout.rect(column: column, row: row)
                if snap {
                    let x0 = r.x.rounded(), y0 = r.y.rounded()
                    let x1 = max(x0 + 1, (r.x + r.width).rounded())
                    let y1 = max(y0 + 1, (r.y + r.height).rounded())
                    r = (x0, y0, x1 - x0, y1 - y0)
                }
                let index = StripePalette.index(column: column, row: row,
                                                columns: field.columns, rows: field.rows)
                cells.append(Cell(x: r.x, y: r.y, width: r.width, height: r.height,
                                  color: StripePalette.stops[index]))
            }
        }
        return cells
    }
}
