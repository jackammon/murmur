import AppKit
import QuartzCore
import SwiftUI
import Combine
import MurmurKit
import MurmurDesign

/// SPEC-004 — floating recording overlay.
///
/// A small HUD near the top of the screen surfacing recording / transcribing
/// state independently of the menu-bar icon. Click-through; never steals focus.
/// Lifecycle is driven by `AppState.phase` via Combine — we never call
/// show/hide directly from the orchestrator.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayPill>?
    private var cancellable: AnyCancellable?
    private let state: AppState
    private let model = OverlayModel()

    init(state: AppState) {
        self.state = state
        cancellable = state.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.handle(phase: phase)
            }
    }

    /// Long enough to read an instruction like "sign in again in Settings".
    private static let errorLinger: TimeInterval = 6
    /// Long enough to read "Copied to clipboard" or an interruption notice.
    private static let messageLinger: TimeInterval = 1.6

    private func handle(phase: AppState.Phase) {
        switch phase {
        case .recording, .transcribing, .polishing:
            model.paste = nil
            ensurePanel()
            resizePanel()
            showAnimated()
        case .ready:
            guard panel?.isVisible == true else { return }
            if OverlayPill.readyShowsMessage(state) {
                // Something to read: show it, then close.
                resizePanel()
                hide(after: Self.messageLinger, duration: 0.25)
            } else {
                // Pasted: play the paste animation inside the pill, then the
                // whole HUD — surface, dots and clock together — fades out.
                let animation = PasteAnimation(
                    rawValue: UserDefaults.standard.string(forKey: PasteAnimation.defaultsKey) ?? ""
                ) ?? .default
                model.paste = OverlayModel.Paste(
                    animation: animation, start: Date(),
                    heights: DotGrid.hud.workingHeights(time: Date().timeIntervalSinceReferenceDate)
                )
                resizePanel()
                let fadeAt = PasteAnimation.duration * PasteAnimation.fadeStart
                hide(after: fadeAt, duration: PasteAnimation.duration - fadeAt)
            }
        case .error:
            // A failure must never look like a dictation that simply vanished:
            // show what went wrong, and hold long enough to read a sentence.
            model.paste = nil
            ensurePanel()
            resizePanel()
            showAnimated()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.errorLinger) { [weak self] in
                if case .error = self?.state.phase {
                    self?.hideAnimated(duration: 0.25)
                }
            }
        case .idle, .warming, .starting:
            hideAnimated(duration: 0.25)
        }
    }

    /// Hide after `delay` unless a new dictation has started meanwhile.
    private func hide(after delay: TimeInterval, duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if case .ready = self?.state.phase {
                self?.hideAnimated(duration: duration)
            }
        }
    }

    private func ensurePanel() {
        if panel != nil { return }

        let pill = OverlayPill(state: state, model: model)
        let host = NSHostingView(rootView: pill)
        host.frame = NSRect(origin: .zero, size: OverlayPill.size(for: state, pasting: model.paste != nil))

        let panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        positionTopCentre(panel: panel)

        self.panel = panel
        self.hostingView = host
    }

    /// Match the window to the SwiftUI frame for the current state. Keeps the
    /// top edge and horizontal centre in place so the HUD doesn't drift when,
    /// say, the Overlay card becomes the compact pill.
    private func resizePanel() {
        guard let panel else { return }
        let size = OverlayPill.size(for: state, pasting: model.paste != nil)
        guard panel.frame.size != size else { return }
        let old = panel.frame
        panel.setFrame(NSRect(x: (old.midX - size.width / 2).rounded(),
                              y: old.maxY - size.height,
                              width: size.width, height: size.height),
                       display: panel.isVisible)
        hostingView?.frame = NSRect(origin: .zero, size: size)
    }

    private func positionTopCentre(panel: NSPanel) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panel.frame.width / 2
        let y = visible.maxY - panel.frame.height - Theme.s24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func showAnimated() {
        guard let panel else { return }
        if panel.isVisible && panel.alphaValue > 0.95 { return }
        positionTopCentre(panel: panel)
        // `orderFrontRegardless` (not `orderFront`): we're a background accessory
        // app, so this surfaces the pill onto the currently active Space —
        // including another app's fullscreen Space — without stealing focus.
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hideAnimated(duration: TimeInterval) {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            // A new dictation may have started during the fade.
            guard let self, !self.isShowingPhase else { return }
            panel?.orderOut(nil)
            self.model.paste = nil
        })
    }

    private var isShowingPhase: Bool {
        switch state.phase {
        case .recording, .transcribing, .polishing, .error: return true
        default: return false
        }
    }
}

/// Overlay-only presentation state the controller shares with the view.
@MainActor
final class OverlayModel: ObservableObject {
    struct Paste: Equatable {
        let animation: PasteAnimation
        let start: Date
        let heights: [Double]
    }

    /// Set while the paste animation plays.
    @Published var paste: Paste?
}

// MARK: - SwiftUI pill

/// The listening HUD.
///
/// Batch and Inline get a compact pill: the round-stipple wave and the
/// recording clock, nothing else. The clock stays until the pill closes.
/// Transcribing keeps the pill and swaps the wave for a slow swell. A paste
/// plays a short animation in the dots; then the whole pill fades. Overlay
/// mode gets a card with the live transcript under the same wave and clock.
/// Words appear only when there is something to read: "Copied to
/// clipboard", an interruption notice, an error. The surface follows the
/// Settings HUD style, independent of the system appearance by default, like
/// the system's own HUDs.
struct OverlayPill: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: OverlayModel
    @AppStorage(HUDStyle.defaultsKey) private var style: HUDStyle = .dark
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let size = Self.size(for: state, pasting: model.paste != nil)
        let shape = RoundedRectangle(cornerRadius: size.height <= 40 ? size.height / 2 : Theme.rFloating,
                                     style: .continuous)
        let dark = style.isDark(systemIsDark: systemScheme == .dark)
        Group {
            if isOverlayRecording {
                transcriptPreview
            } else if let message = Self.message(for: state) {
                messagePill(message)
            } else {
                compactPill
            }
        }
        .frame(width: size.width, height: size.height)
        .background {
            ZStack {
                VisualEffect(material: .hudWindow, blending: .behindWindow,
                             appearance: dark ? .darkAqua : .aqua)
                (dark ? Color.black.opacity(0.55) : Color.white.opacity(0.6))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    // MARK: sizes

    static let compactHeight: CGFloat = 34

    /// The panel size for the current state.
    static func size(for state: AppState, pasting: Bool) -> CGSize {
        if case .recording = state.phase, state.activeDictationMode == .overlay {
            return CGSize(width: 440, height: 150)
        }
        if case .error = state.phase { return CGSize(width: 360, height: 72) }
        if !pasting, message(for: state) != nil { return CGSize(width: 300, height: compactHeight) }
        let chips = (showsKickoffChip(state) ? 64 : 0) + (showsRemoteChip(state) ? 70 : 0)
        return CGSize(width: 112 + CGFloat(chips), height: compactHeight)
    }

    /// Whether `.ready` has words to show instead of the paste animation.
    static func readyShowsMessage(_ state: AppState) -> Bool {
        guard case .ready = state.phase else { return false }
        return message(for: state) != nil
    }

    // MARK: compact pill

    private var compactPill: some View {
        HStack(spacing: 10) {
            DotWave(motion: waveMotion)
                .frame(width: 44, height: 18)
            Spacer(minLength: 0)
            // Both chips can coexist: a kickoff recording with a remote
            // backend uploads audio *and* routes the transcript to claude —
            // each network hop gets disclosed.
            if Self.showsKickoffChip(state) { NetworkChip(label: "claude") }
            if Self.showsRemoteChip(state) { NetworkChip(label: "remote") }
            clock
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityStatus)
    }

    private var waveMotion: DotWaveMotion {
        if let paste = model.paste {
            return .paste(paste.animation, start: paste.start, heights: paste.heights)
        }
        switch state.phase {
        case .recording, .starting: return .live(state.levelHistory)
        case .transcribing, .polishing: return .working
        case .error: return .alert
        default: return .quiet
        }
    }

    private var clock: some View {
        Text(ElapsedTime.format(state.elapsedSeconds))
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 26, alignment: .trailing)
    }

    private var accessibilityStatus: String {
        let time = ElapsedTime.spoken(state.elapsedSeconds)
        switch state.phase {
        case .recording: return "Listening, \(time)"
        case .transcribing:
            // SPEC-044 — never claim local processing while audio goes remote.
            return state.remoteHost.map { "Transcribing via \($0)" } ?? "Transcribing on your Mac"
        case .polishing: return "Polishing"
        case .ready: return state.lastPasted ? "Pasted" : "Done"
        default: return "Murmur"
        }
    }

    // MARK: message pill

    struct Message {
        let title: String
        let detail: String?
    }

    /// Words to show, or nil when the dots say it all.
    static func message(for state: AppState) -> Message? {
        switch state.phase {
        case .ready:
            // SPEC-036 — an interruption notice always gets read.
            if let notice = state.lastNotice {
                return Message(title: state.lastPasted ? "Pasted" : "Copied to clipboard", detail: notice)
            }
            if state.recordingMode == .agentKickoff {
                if state.lastKickoffSucceeded { return Message(title: "Launched claude", detail: nil) }
                return Message(title: "Kickoff failed",
                               detail: state.lastKickoffError ?? "Transcript copied to clipboard")
            }
            if state.lastPasted { return nil }
            return Message(title: "Copied to clipboard", detail: "Press ⌘V to paste")
        case .error(let message):
            return Message(title: "Dictation failed", detail: message)
        default:
            return nil
        }
    }

    private func messagePill(_ message: Message) -> some View {
        var isError = false
        if case .error = state.phase { isError = true }
        return HStack(spacing: 12) {
            DotWave(motion: isError ? .alert : .quiet)
                .frame(width: 44, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(message.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let detail = message.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(isError ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: isError)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: overlay-mode card

    private var isOverlayRecording: Bool {
        guard case .recording = state.phase else { return false }
        return state.activeDictationMode == .overlay
    }

    /// Overlay mode needs a readable transcript surface rather than the
    /// compact pill used by Batch and Inline.
    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DotWave(motion: .live(state.levelHistory))
                    .frame(width: 44, height: 18)
                Spacer()
                if Self.showsKickoffChip(state) { NetworkChip(label: "claude") }
                if Self.showsRemoteChip(state) { NetworkChip(label: "remote") }
                clock
            }
            Text(state.livePreview.isEmpty
                 ? "Listening for words…"
                 : String(state.livePreview.suffix(240)))
                .font(.system(size: 15))
                .foregroundStyle(state.livePreview.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                .accessibilityLabel(previewAccessibilityLabel)
            Text("Rough draft · clean text pastes when you stop")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .accessibilityElement(children: .contain)
    }

    private var previewAccessibilityLabel: String {
        state.livePreview.isEmpty ? "Listening for words" : "Live draft: \(state.livePreview)"
    }

    // MARK: network chips

    /// SPEC-031 — kickoff recordings disclose that the transcript goes to claude.
    static func showsKickoffChip(_ state: AppState) -> Bool {
        guard state.recordingMode == .agentKickoff else { return false }
        if case .recording = state.phase { return true }
        return false
    }

    /// SPEC-044 — the privacy contract's network indicator for remote
    /// transcription: visible the whole time audio destined for the wire is
    /// being captured or sent.
    static func showsRemoteChip(_ state: AppState) -> Bool {
        guard state.remoteHost != nil else { return false }
        switch state.phase {
        case .recording, .transcribing: return true
        default: return false
        }
    }
}

/// SPEC-031 / SPEC-044 network chip — the privacy contract's required
/// indicator that audio or text is leaving the Mac.
private struct NetworkChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "globe")
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.caution)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Theme.caution.opacity(0.16)))
        .overlay(Capsule().strokeBorder(Theme.caution.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("Network: \(label)")
    }
}
