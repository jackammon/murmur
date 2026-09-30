# Murmur visual design

Murmur should feel like part of macOS: system fonts, semantic colours that follow light and dark appearance, and native controls. Two monochrome marks carry the brand. There is no brand colour.

## Lean mark

The logo is four pills tilted at 70°, like quick handwriting, on a 16 × 14 pt box. The drawing's stroke is 2 pt; in the menu bar and popover header it is 2.4 pt so the mark holds its own beside system icons. The same geometry draws every size:

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

Batch and Inline use a 34 pt tall pill, borderless with a soft shadow: the dot wave on the left and the recording clock on the right. The clock stays until the HUD closes. Overlay mode uses only a 440 × 150 card, for the whole dictation: the same wave and clock above the live draft, a Stop button while recording, the clean text once it lands, and the paste animation in its dots. The card is the only HUD surface that takes clicks, and only for Stop; the panel never activates Murmur, so the paste still lands in the app you were using. Network chips (SPEC-031, SPEC-044) appear beside the clock when audio or text leaves the Mac.

Settings → General → Appearance has two choices:

- **Listening HUD**: Dark (default), Light, or Match system (`murmur.hudStyle`).
- **When text is pasted**: Fill and dissolve (default) or Star (`murmur.pasteAnimation`).

## Colour (optional)

Settings → General → Appearance → **Colour** adds the reference GIF's palette on top of the monochrome design (`murmur.colourTheme`, Off by default). It colours the listening HUD and Overlay card, the About and onboarding mark, and the Dock icon while Murmur runs (Finder keeps the Paper icon from the bundle). The menu bar stays monochrome.

There are 18 themes in five groups: **Field** (Sunrise, Lagoon, Dusk, Ember, Every still), **Wash** (Blush wash, Dawn, Lagoon wash), **Horizon** (Sunrise horizon, Dusk horizon, Blush horizon, Ember slant), **Duotone** (Citrus, Tide), and **Rim and grain** (Sunrise rim, Dusk rim, Big pixel, Fine grain). Every theme keeps colour in large areas, dithered (Bayer 4 × 4) only where two colours meet, with a dark or pale scrim, dark ink, or a soft halo under light dots so the HUD stays readable. The colour drifts only while you speak. Every still moves through all five palettes, dissolving from one to the next every 6 s.

## Code

- `Sources/MurmurDesign` (Foundation only, unit tested): `LeanMark` geometry, `DotGrid` rules, `PasteAnimation` frames, `HUDStyle`, `ColourTheme` fields, `ElapsedTime`.
- `Sources/MurmurApp/ColourSurface.swift`: the colour field renderer, themed icon tile, and Dock icon swap.
- `Sources/MurmurApp/Marks.swift`: SwiftUI and AppKit renderers (`DotWave`, `LeanMarkShape`, `MurmurMark`, `StatusGlyph`).
- `scripts/icon/main.swift`: compiled with `Sources/MurmurDesign` by `scripts/wrap_app.sh` to build `AppIcon.icns`.
- `Theme.swift`: spacing, radii, system status colours (`success`, `caution`, `alert`), type roles, and a monochrome button style. Prefer native controls in new UI.
