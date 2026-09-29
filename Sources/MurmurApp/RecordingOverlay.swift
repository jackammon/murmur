import AppKit
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

    private func handle(phase: AppState.Phase) {
        switch phase {
        case .recording, .transcribing, .polishing:
            ensurePanel()
            resizePanel(for: phase)
            showAnimated()
        case .ready:
            // Linger briefly so the user sees the "Pasted" / "Copied" state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                if case .ready = self?.state.phase {
                    self?.hideAnimated()
                }
            }
        case .error:
            // A failure must never look like a dictation that simply vanished:
            // show what went wrong, and hold long enough to read a sentence.
            ensurePanel()
            resizePanel(for: phase)
            showAnimated()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.errorLinger) { [weak self] in
                if case .error = self?.state.phase {
                    self?.hideAnimated()
                }
            }
        case .idle, .warming, .starting:
            hideAnimated()
        }
    }

    private func ensurePanel() {
        if panel != nil { return }

        let pill = OverlayPill(state: state)
        let host = NSHostingView(rootView: pill)
        host.frame = NSRect(origin: .zero, size: OverlayPill.size(for: state.phase,
                                                                mode: state.activeDictationMode))

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

    /// The panel is created at one size; an error pill is bigger, so match the
    /// window to the SwiftUI frame before showing it or the content clips.
    private func resizePanel(for phase: AppState.Phase) {
        guard let panel else { return }
        let size = OverlayPill.size(for: phase, mode: state.activeDictationMode)
        guard panel.frame.size != size else { return }
        panel.setContentSize(size)
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

    private func hideAnimated() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }
}

// MARK: - SwiftUI pill

/// The listening HUD.
///
/// Batch and Inline get a compact capsule: stripe wave, one or two lines of
/// status, and the recording clock. Overlay mode gets a card with the live
/// transcript under the same header. The surface and ink follow the
/// Settings stripe style — colour or white stripes on a dark HUD, or black
/// stripes on a light one — independent of the system appearance, like the
/// system's own HUDs.
struct OverlayPill: View {
    @ObservedObject var state: AppState
    @AppStorage(StripeStyle.defaultsKey) private var style: StripeStyle = .color

    var body: some View {
        let size = Self.size(for: state.phase, mode: state.activeDictationMode)
        let shape = RoundedRectangle(cornerRadius: cornerRadius(for: size), style: .continuous)
        Group {
            if isOverlayRecording {
                transcriptPreview
            } else {
                statusPill
            }
        }
        .frame(width: size.width, height: size.height)
        .background {
            ZStack {
                VisualEffect(material: .hudWindow, blending: .behindWindow,
                             appearance: style.hasDarkSurface ? .darkAqua : .aqua)
                (style.hasDarkSurface ? Color.black.opacity(0.55) : Color.white.opacity(0.55))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, style.hasDarkSurface ? .dark : .light)
    }

    /// Capsule for the one-line phases; a softer card for bigger panels.
    private func cornerRadius(for size: CGSize) -> CGFloat {
        size.height <= 52 ? size.height / 2 : Theme.rFloating
    }

    private var isOverlayRecording: Bool {
        guard case .recording = state.phase else { return false }
        return state.activeDictationMode == .overlay
    }

    private var ink: StripeInk { style.usesPalette ? .palette : .foreground }

    // MARK: overlay-mode card

    /// Overlay mode needs a readable transcript surface rather than the
    /// one-line status pill used by Batch and Inline.
    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StripeWave(motion: .live(state.levelHistory), ink: ink)
                    .frame(width: 46, height: 20)
                Text("Listening")
                    .font(.murmurHeadline)
                Spacer()
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

    // MARK: status capsule

    private var statusPill: some View {
        HStack(spacing: 10) {
            indicator
                .frame(width: 56, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.murmurHeadline)
                    .lineLimit(1)
                if let subline = plainSubline {
                    Text(subline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(isError ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: isError)
                }
            }
            Spacer(minLength: 0)
            // Both chips can coexist: a kickoff recording with a remote
            // backend uploads audio *and* routes the transcript to claude —
            // each network hop gets disclosed.
            if state.recordingMode == .agentKickoff,
               case .recording = state.phase {
                NetworkChip(label: "claude")
            }
            if showsRemoteChip {
                NetworkChip(label: "remote")
            }
            if case .recording = state.phase {
                clock
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .accessibilityElement(children: .combine)
    }

    private var clock: some View {
        Text(ElapsedTime.format(state.elapsedSeconds))
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel(ElapsedTime.spoken(state.elapsedSeconds))
    }

    /// The stripe field carries the state: live while listening, a travelling
    /// wave that fills with colour as transcription progresses, a quiet line
    /// when done, and an exclamation mark on failure.
    @ViewBuilder
    private var indicator: some View {
        switch state.phase {
        case .recording, .starting:
            StripeWave(motion: .live(state.levelHistory), ink: ink)
        case .transcribing:
            StripeWave(motion: .working, ink: ink, progress: state.transcriptionProgress)
        case .polishing:
            StripeWave(motion: .working, ink: ink)
        case .ready:
            if state.recordingMode == .agentKickoff, !state.lastKickoffSucceeded {
                StripeWave(motion: .alert, ink: alertInk, animated: false)
            } else {
                StripeWave(motion: .quiet, ink: ink, animated: false)
            }
        case .error:
            StripeWave(motion: .alert, ink: alertInk, animated: false)
        default:
            StripeWave(motion: .resting, ink: ink, animated: false)
        }
    }

    private var alertInk: StripeInk { style.usesPalette ? .solid(Theme.alert) : .foreground }

    /// SPEC-044 — the privacy contract's network indicator for remote
    /// transcription: visible the whole time audio destined for the wire is
    /// being captured or sent.
    private var showsRemoteChip: Bool {
        guard state.remoteHost != nil else { return false }
        switch state.phase {
        case .recording, .transcribing: return true
        default: return false
        }
    }

    private var isError: Bool {
        if case .error = state.phase { return true }
        return false
    }

    /// Errors need a bigger pill than the one-line phases.
    static func size(for phase: AppState.Phase, mode: DictationMode) -> CGSize {
        if case .recording = phase, mode == .overlay {
            return CGSize(width: 440, height: 150)
        }
        if case .error = phase { return CGSize(width: 360, height: 72) }
        return CGSize(width: 272, height: 48)
    }

    private var headline: String {
        switch state.phase {
        case .recording:
            return state.recordingMode == .agentKickoff ? "Listening (kickoff)" : "Listening"
        case .transcribing: return "Transcribing"
        case .polishing:    return "Polishing"
        case .ready:
            if state.recordingMode == .agentKickoff {
                return state.lastKickoffSucceeded ? "Launched claude" : "Kickoff failed"
            }
            return state.lastPasted ? "Pasted at cursor" : "Copied to clipboard"
        case .error:        return "Dictation failed"
        default:            return "Murmur"
        }
    }

    private var plainSubline: String? {
        switch state.phase {
        case .recording:
            if state.activeDictationMode == .overlay, !state.livePreview.isEmpty {
                return String(state.livePreview.suffix(52))
            }
            return nil
        case .transcribing:
            // SPEC-044 — never claim "On your Mac" when audio is being sent
            // to a configured remote endpoint.
            if let host = state.remoteHost { return "via \(host)" }
            return "On your Mac"
        case .polishing:
            return "On your Mac"
        case .ready:
            // SPEC-036 — surface an interruption notice over the usual subline.
            if let notice = state.lastNotice { return notice }
            if state.recordingMode == .agentKickoff, !state.lastKickoffSucceeded {
                return state.lastKickoffError ?? "Transcript copied to clipboard"
            }
            return state.lastTranscript.map { String($0.prefix(48)) }
        case .error(let message):
            return message
        default:
            return nil
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
