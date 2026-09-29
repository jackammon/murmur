import SwiftUI
import AppKit

/// Design tokens and shared SwiftUI components.
///
/// Murmur follows the system: system fonts, semantic colours that adapt to
/// light and dark appearances, and native controls where they exist. Brand
/// character lives in one place, the stripe field (`Stripes.swift`), which
/// draws the menu-bar glyph, the listening HUD, and the brand mark.

enum Theme {
    // MARK: - Status colours (system colours adapt to appearance and contrast)

    static let success = Color(nsColor: .systemGreen)
    static let caution = Color(nsColor: .systemOrange)
    static let alert   = Color(nsColor: .systemRed)

    /// 1 pt card stroke — works in both light and dark mode.
    static let hairline = Color.primary.opacity(0.08)

    // MARK: - Spacing scale

    static let s4:  CGFloat = 4
    static let s8:  CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32

    // MARK: - Corner radius scale

    /// Inline pills: status badges, small chips, buttons.
    static let rInline:   CGFloat = 6
    /// Cards: banners, transcript card, settings rows.
    static let rCard:     CGFloat = 10
    /// Floating chrome: the overlay card.
    static let rFloating: CGFloat = 18
}

// MARK: - Typography roles

extension Font {
    /// Onboarding welcome only.
    static let murmurHero     = Font.system(size: 26, weight: .semibold)
    /// Onboarding step titles, About title.
    static let murmurTitle    = Font.system(size: 20, weight: .semibold)
    /// Tagline under the About and welcome titles.
    static let murmurTagline  = Font.system(size: 13)
    /// Overlay headline, settings group titles.
    static let murmurHeadline = Font.system(size: 13, weight: .semibold)
}

// MARK: - SectionHeader

/// Group label in the style of System Settings. Use above any logical group
/// of content.
struct SectionHeader: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - PlaceholderTextEditor

/// `TextEditor` with a `prompt` shown when empty. Encapsulates the
/// previously-duplicated "ZStack { Text if empty; TextEditor }" pattern.
struct PlaceholderTextEditor: View {
    @Binding var text: String
    let prompt: String
    var monospaced: Bool = false
    var minHeight: CGFloat = 80
    var idealHeight: CGFloat? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .foregroundStyle(.secondary)
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .frame(minHeight: minHeight, idealHeight: idealHeight ?? minHeight)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rCard)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
    }
}

// MARK: - Card modifier

extension View {
    /// Standard card: subtle fill + 1 pt hairline stroke + rounded corners +
    /// internal padding. Used for transcript cards, banners, privacy rows.
    func murmurCard(padding: CGFloat = Theme.s12) -> some View {
        self
            .padding(padding)
            .background(Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
    }
}

// MARK: - Tinted banner modifier

/// Soft-fill + same-hue stroke banner for notices in Settings.
extension View {
    func murmurBanner(tint: Color, padding: CGFloat = Theme.s12) -> some View {
        self
            .padding(padding)
            .background(tint.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
    }
}

// MARK: - Buttons

/// Design-system button, three variants. Monochrome so it sits with the
/// stripe mark, and adaptive so it reads in light and dark mode.
///
/// - `.neutral`     — quiet tinted fill. Default ask, like "Export".
/// - `.primary`     — solid label-colour fill (black in light mode, white in
///                    dark). The page's main CTA; one per surface at most.
/// - `.destructive` — red fill. Anything irreversible.
struct MurmurButtonStyle: ButtonStyle {
    enum Variant { case neutral, primary, destructive }
    var variant: Variant = .neutral
    var size: Size = .regular
    enum Size { case small, regular }

    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: Theme.rInline, style: .continuous)
        configuration.label
            .font(font)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .frame(minHeight: minHeight)
            .background(background(pressed: pressed), in: shape)
            .overlay(shape.strokeBorder(strokeColor, lineWidth: 1))
            .foregroundStyle(textColor)
            .opacity(enabled ? 1.0 : 0.4)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }

    private var font: Font {
        size == .small ? .caption.weight(.medium) : .callout.weight(.medium)
    }
    private var hPad: CGFloat { size == .small ? Theme.s8 : Theme.s12 }
    private var vPad: CGFloat { size == .small ? 3 : 5 }
    private var minHeight: CGFloat { size == .small ? 22 : 28 }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .neutral:     return Color.primary.opacity(pressed ? 0.14 : 0.07)
        case .primary:     return Color.primary.opacity(pressed ? 0.75 : 0.9)
        case .destructive: return Theme.alert.opacity(pressed ? 0.8 : 0.92)
        }
    }

    private var strokeColor: Color {
        switch variant {
        case .neutral:     return Color.primary.opacity(0.08)
        case .primary:     return .clear
        case .destructive: return .clear
        }
    }

    private var textColor: Color {
        switch variant {
        case .neutral:     return .primary
        case .primary:     return Color(nsColor: .windowBackgroundColor)
        case .destructive: return .white
        }
    }
}

extension ButtonStyle where Self == MurmurButtonStyle {
    static var murmurNeutral: MurmurButtonStyle { MurmurButtonStyle(variant: .neutral) }
    static var murmurPrimary: MurmurButtonStyle { MurmurButtonStyle(variant: .primary) }
    static var murmurDestructive: MurmurButtonStyle { MurmurButtonStyle(variant: .destructive) }
    static var murmurNeutralSmall: MurmurButtonStyle { MurmurButtonStyle(variant: .neutral, size: .small) }
    static var murmurPrimarySmall: MurmurButtonStyle { MurmurButtonStyle(variant: .primary, size: .small) }
    static var murmurDestructiveSmall: MurmurButtonStyle { MurmurButtonStyle(variant: .destructive, size: .small) }
}

// MARK: - Visual effect

/// `NSVisualEffectView` bridge. `appearance` pins the material to light or
/// dark regardless of the system setting (used by the overlay HUD).
struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    var appearance: NSAppearance.Name? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.state = .active
        updateNSView(v, context: context)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
        nsView.appearance = appearance.flatMap(NSAppearance.init(named:))
    }
}
