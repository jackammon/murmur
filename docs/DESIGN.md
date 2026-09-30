# Murmur visual design

Murmur should feel like part of macOS: system fonts, semantic colours that follow light and dark appearance, and native controls. Two monochrome marks carry the brand. There is no brand colour.

## Lean mark

The logo is four pills tilted at 70°, like quick handwriting. At menu-bar size the pills are 2 pt thick on a 16 × 14 pt box. The same geometry draws every size:

| Surface | Drawing |
| --- | --- |
| Menu-bar icon (template image) | At rest: the mark. While listening: each pill's length follows the microphone. Loading and transcribing: dimmed. Error: a tilted exclamation mark in the same pills. Update ready: a small dot at the top right. |
| Popover header | The mark in the label colour |
| About, onboarding | The mark on a Paper tile, like the app icon |
| App icon | The mark scaled up exactly, warm ink `#17140F` on flat Paper `#F7F5F1`, no gradient |

## Round-stipple dot wave

The listening HUD and the popover's live wave are an 11 × 7 grid of round dots (the popover uses 29 columns to span its width). Only lit dots are drawn.

- **Listening**: the newest level lights the centre column and older levels ripple out to both edges. Heights glide between audio updates rather than stepping.
- **Transcribing and polishing**: a slow swell travels through the grid.
- **Pasted**: a paste animation plays inside the grid, then the whole HUD fades together (surface, dots and clock). The animation lasts 1 s; the fade starts at 0.72 s.
  - **Fill and dissolve** (default): the grid floods with dots from the centre, holds, then the dots wink out in a scattered order.
  - **Star**: the dots gather to the centre, a four-pointed star shoots out to the grid's edges, and its arms run off the ends.
- **Words appear only when there is something to read**: "Copied to clipboard" when paste was not possible, an interruption notice, or an error with an exclamation mark in the dots.
- **Reduce Motion** stops all animation; after a paste the HUD simply fades.

## HUD

A 34 pt tall pill, borderless with a soft shadow: the dot wave on the left and the recording clock on the right. The clock stays until the HUD closes. Overlay mode uses a 440 × 150 card with the same wave and clock above the live draft. Network chips (SPEC-031, SPEC-044) appear beside the clock when audio or text leaves the Mac.

Settings → General → Appearance has two choices:

- **Listening HUD**: Dark (default), Light, or Match system (`murmur.hudStyle`).
- **When text is pasted**: Fill and dissolve (default) or Star (`murmur.pasteAnimation`).

## Code

- `Sources/MurmurDesign` (Foundation only, unit tested): `LeanMark` geometry, `DotGrid` rules, `PasteAnimation` frames, `HUDStyle`, `ElapsedTime`.
- `Sources/MurmurApp/Marks.swift`: SwiftUI and AppKit renderers (`DotWave`, `LeanMarkShape`, `MurmurMark`, `StatusGlyph`).
- `scripts/icon/main.swift`: compiled with `Sources/MurmurDesign` by `scripts/wrap_app.sh` to build `AppIcon.icns`.
- `Theme.swift`: spacing, radii, system status colours (`success`, `caution`, `alert`), type roles, and a monochrome button style. Prefer native controls in new UI.
