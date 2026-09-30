// Generates build/AppIcon.icns: the Lean mark — four tilted pills — in warm
// ink on a flat Paper rounded square.
//
// Compiled together with the MurmurDesign sources so the icon uses exactly
// the geometry the menu bar draws (see `LeanMark`). `wrap_app.sh` runs:
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

// Flat Paper tile and warm near-black ink. No gradient.
let paper = NSColor(srgbRed: 0.969, green: 0.961, blue: 0.945, alpha: 1)  // #F7F5F1
let ink   = NSColor(srgbRed: 0.090, green: 0.078, blue: 0.059, alpha: 1)  // #17140F

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
    paper.setFill()
    tilePath.fill()

    // Hairline rim so the light tile holds its edge on light Docks.
    NSColor.black.withAlphaComponent(0.1).setStroke()
    let rimInset = max(0.5, inner * 0.003)
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: rimInset, dy: rimInset),
                           xRadius: radius - rimInset, yRadius: radius - rimInset)
    rim.lineWidth = max(0.5, inner * 0.004)
    rim.stroke()

    // The mark, centred: the menu-bar geometry scaled up, drawn larger at
    // small sizes so the pills survive. Pills come y-down; AppKit is y-up.
    let share = side <= 32 ? 0.66 : 0.56
    let k = Double(inner) * share / LeanMark.width
    let originX = Double(tile.midX) - LeanMark.width * k / 2
    let originTop = Double(s - tile.midY) - LeanMark.height * k / 2
    let thickness = max(side <= 16 ? 1.5 : 1, LeanMark.thickness * k)
    let angle = LeanMark.tilt * .pi / 180
    ink.setStroke()
    for pill in LeanMark.pills {
        let half = max(0, pill.length - LeanMark.thickness) / 2 * k
        let cx = originX + pill.centreX * k, cy = originTop + pill.centreY * k
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx - cos(angle) * half, y: Double(s) - (cy - sin(angle) * half)))
        path.line(to: NSPoint(x: cx + cos(angle) * half, y: Double(s) - (cy + sin(angle) * half)))
        path.lineWidth = thickness
        path.lineCapStyle = .round
        path.stroke()
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

print("→ Rendering \(layouts.count) sizes of the Lean mark...")
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
