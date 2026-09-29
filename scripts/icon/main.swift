// Generates build/AppIcon.icns: the stripe-field brand mark in the dithered
// palette on a near-black rounded square.
//
// Compiled together with the MurmurDesign sources so the icon uses the exact
// geometry and colours the app draws (see `StripeMark`). `wrap_app.sh` runs:
//
//   swiftc -O scripts/icon/main.swift Sources/MurmurDesign/*.swift -o build/make_icon
//   build/make_icon

import AppKit
import Foundation

let cwd = FileManager.default.currentDirectoryPath
let buildDir   = URL(fileURLWithPath: cwd).appendingPathComponent("build")
let iconsetDir = buildDir.appendingPathComponent("AppIcon.iconset")
let icnsURL    = buildDir.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Tile gradient, top to bottom.
let tileTop    = NSColor(srgbRed: 0.125, green: 0.125, blue: 0.137, alpha: 1)  // #202023
let tileBottom = NSColor(srgbRed: 0.063, green: 0.063, blue: 0.075, alpha: 1)  // #101013

// macOS icon template: the visible rounded square is ~824 px on a 1024
// canvas, leaving ~100 px transparent margin per side so the icon lines up
// with system apps in the Dock and Finder.
let iconMarginFraction: CGFloat = 100.0 / 1024.0

func renderIcon(side: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .none

    let s = CGFloat(side)
    let margin = (s * iconMarginFraction).rounded()
    let inner = s - margin * 2
    let tile = NSRect(x: margin, y: margin, width: inner, height: inner)
    let radius = inner * 0.225

    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    NSGradient(starting: tileTop, ending: tileBottom)!.draw(in: tilePath, angle: -90)

    // Faint rim so the tile holds its edge on dark Docks.
    NSColor.white.withAlphaComponent(0.06).setStroke()
    let rimInset = max(0.5, inner * 0.004)
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: rimInset, dy: rimInset),
                           xRadius: radius - rimInset, yRadius: radius - rimInset)
    rim.lineWidth = max(1, inner * 0.006)
    rim.stroke()

    // The mark, centred. Cells come top-left-origin; AppKit is bottom-left.
    let scale = StripeMark.scale(forTileSide: Double(inner))
    let markW = (Double(inner) * scale.width).rounded()
    let markH = (Double(inner) * scale.height).rounded()
    let snap = side <= 64
    var originX = Double(tile.midX) - markW / 2
    var originTop = Double(s - tile.midY) - markH / 2
    if snap { originX.round(); originTop.round() }

    context.shouldAntialias = !snap
    for cell in StripeMark.cells(width: markW, height: markH, snap: snap) {
        NSColor(srgbRed: cell.color.red, green: cell.color.green, blue: cell.color.blue, alpha: 1).setFill()
        let top = originTop + cell.y
        NSRect(x: originX + cell.x,
               y: Double(s) - top - cell.height,
               width: cell.width, height: cell.height).fill()
    }
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, name: String) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make_icon", code: 1)
    }
    try png.write(to: iconsetDir.appendingPathComponent(name))
    print("  ✓ \(name) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}

// .iconset canonical filename × size table.
let layouts: [(side: Int, name: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

print("→ Rendering \(layouts.count) sizes of the stripe mark...")
for layout in layouts {
    try writePNG(renderIcon(side: layout.side), name: layout.name)
}

print("→ Packing AppIcon.icns...")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["--convert", "icns", iconsetDir.path, "--output", icnsURL.path]
try p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else {
    print("error: iconutil failed (code \(p.terminationStatus))")
    exit(1)
}

print("✓ \(icnsURL.path)")
try? FileManager.default.removeItem(at: iconsetDir)
