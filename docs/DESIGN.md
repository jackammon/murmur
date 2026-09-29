# Murmur visual design

Murmur should feel like part of macOS: system fonts, semantic colours that follow light and dark appearance, and native controls. One element carries the brand: the **stripe field**.

## Stripe field

Every mark is a grid of short vertical segments. Columns stand for slices of sound. Each column has small breaks, which give the stripes their texture. The same field draws:

| Surface | Motion | Ink |
| --- | --- | --- |
| Menu-bar icon (template, 20×16 pt) | Resting mark; live levels while recording; quiet line while transcribing; `!` on error; dimmed while the model loads | Menu-bar text colour |
| Popover header | Resting mark | Label colour |
| Popover live wave | Live levels while recording; travelling wave while transcribing | Stripe style |
| Listening HUD | Same as the live wave, plus quiet line when pasted and `!` on failure | Stripe style |
| About, onboarding, app icon | Resting mark on a dark tile | Palette |

The geometry, palette, and dither rules live in `Sources/MurmurDesign` (Foundation only, unit tested). `Sources/MurmurApp/Stripes.swift` renders them with SwiftUI `Canvas` and AppKit. `scripts/icon/main.swift` compiles with the same sources to build `AppIcon.icns`.

- **Live levels**: the newest level sits in the centre column and older levels ripple outward, so speech reads as a symmetric pulse.
- **Breaks**: the resting mark has one authored break per column. Live fields break more often near the tips, and the pattern changes six times a second. The menu-bar glyph never flickers, and Reduce Motion stops all animation.
- **Palette**: colours are sampled from the reference stills and grouped into five scenes: sunrise, lagoon, dusk, blush, and ember. A field shows one scene as a left-to-right gradient with a 4×4 ordered dither between neighbouring colours. It holds each scene for 3.5 s, then dissolves cell by cell into the next over 1.5 s. Still marks use the first scene.

## Stripe style

Settings → General → Appearance offers **Color**, **White on black**, and **Black on white** (`murmur.stripeStyle`). It sets the HUD surface and ink and the popover's live wave. The popover itself follows the system appearance; in the two monochrome styles its wave uses the label colour.

## Tokens

`Theme.swift` holds spacing, radii, system status colours (`success`, `caution`, `alert`), type roles, and a monochrome button style. Prefer native controls (`.borderedProminent`, `.bordered`, segmented pickers) in new UI.
