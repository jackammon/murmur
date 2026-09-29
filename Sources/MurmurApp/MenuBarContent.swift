import SwiftUI
import AppKit
import MurmurKit
import MurmurDesign

/// Popover that appears on left-click of the menu-bar icon.
///
/// Laid out like the system's own menu-bar extras: a compact header with the
/// stripe mark, status, and shortcut; the dictation button and mode picker;
/// notices only when something needs attention; the last transcript; and
/// menu-style rows for Settings and Quit. While dictating, a live stripe
/// wave appears under the header, inked per the Settings stripe style.
struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @AppStorage("dictationMode") private var dictationMode: String = DictationMode.batch.rawValue
    @AppStorage(StripeStyle.defaultsKey) private var stripeStyle: StripeStyle = .color

    private static let inset: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Self.inset)
                .padding(.top, Self.inset)
                .padding(.bottom, Theme.s12)

            activityWave

            VStack(alignment: .leading, spacing: Theme.s8) {
                recordButton
                modePicker
            }
            .padding(.horizontal, Self.inset)
            .padding(.bottom, Theme.s12)

            if hasNotices {
                sectionDivider
                VStack(alignment: .leading, spacing: 0) { notices }
                    .padding(.vertical, 6)
            }

            if let transcript = state.lastTranscript, !transcript.isEmpty {
                sectionDivider
                transcriptSection(transcript)
                    .padding(.horizontal, Self.inset)
                    .padding(.vertical, Theme.s12)
            }

            sectionDivider
            VStack(spacing: 0) {
                MenuRow(title: "Settings…", shortcut: "⌘,") {
                    (NSApp.delegate as? AppDelegate)?.popoverShowSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                MenuRow(title: "Quit Murmur", shortcut: "⌘Q") {
                    (NSApp.delegate as? AppDelegate)?.popoverQuitApp()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(5)
        }
        .frame(width: 280)
    }

    private var sectionDivider: some View {
        Divider().padding(.horizontal, Self.inset)
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            StripeWave(motion: .resting, ink: .foreground, metrics: .compact, animated: false)
                .frame(width: 20, height: 16)
                .foregroundStyle(.primary)
                .opacity(isWarming ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text("Murmur")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.s8)
            if state.phase == .recording {
                Text(ElapsedTime.format(state.elapsedSeconds))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Recording time \(ElapsedTime.spoken(state.elapsedSeconds))")
            } else {
                KeyCap(text: HotkeyDisplay.current)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isWarming: Bool {
        if case .warming = state.phase { return true }
        return false
    }

    /// Live stripes while listening; a travelling wave while transcribing,
    /// with columns lighting up as progress arrives.
    @ViewBuilder
    private var activityWave: some View {
        let ink: StripeInk = stripeStyle.usesPalette ? .palette : .foreground
        switch state.phase {
        case .starting, .recording:
            StripeWave(motion: .live(state.levelHistory), ink: ink)
                .frame(height: 28)
                .padding(.horizontal, Self.inset)
                .padding(.bottom, Theme.s12)
                .accessibilityHidden(true)
        case .transcribing, .polishing:
            StripeWave(motion: .working, ink: ink,
                       progress: state.phase == .transcribing ? state.transcriptionProgress : nil)
                .frame(height: 28)
                .padding(.horizontal, Self.inset)
                .padding(.bottom, Theme.s12)
                .accessibilityHidden(true)
        default:
            EmptyView()
        }
    }

    private var statusLine: String {
        switch state.phase {
        case .warming:      return "Loading the speech model…"
        case .idle:         return "Ready to dictate"
        case .starting:     return "Starting the microphone…"
        case .recording:    return "Listening…"
        case .transcribing:
            // SPEC-044 — never claim locality while a remote backend runs.
            return state.remoteHost.map { "Transcribing via \($0)…" } ?? "Transcribing on your Mac…"
        case .polishing:    return "Polishing…"
        case .ready:        return state.lastPasted ? "Pasted at cursor" : "Copied to clipboard"
        case .error(let message): return message
        }
    }

    // MARK: - controls

    private var isRecording: Bool { state.phase == .recording }

    private var recordButton: some View {
        Button {
            (NSApp.delegate as? AppDelegate)?.popoverToggleRecording()
        } label: {
            Label(recordingButtonTitle, systemImage: isRecording ? "stop.fill" : "mic.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(isRecording ? Theme.alert : nil)
        .disabled(!recordingButtonEnabled)
        .accessibilityHint("Shortcut: \(HotkeyDisplay.current)")
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Dictation mode", selection: $dictationMode) {
                ForEach(DictationMode.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Dictation mode")
            Text(modeSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeSummary: String {
        switch DictationMode.fromStored(dictationMode) {
        case .batch:   return "Pastes the full transcript when you stop."
        case .overlay: return "Shows a live draft, then pastes clean text when you stop."
        case .inline:  return "Pastes each phrase as you finish speaking."
        }
    }

    private var recordingButtonEnabled: Bool {
        switch state.phase {
        case .idle, .ready, .error, .recording: return true
        case .warming, .starting, .transcribing, .polishing: return false
        }
    }

    private var recordingButtonTitle: String {
        switch state.phase {
        case .idle, .ready, .error: return "Start Dictation"
        case .recording:
            return state.recordingMode == .agentKickoff ? "Stop Recording" : "Stop Dictation"
        case .warming: return "Loading Model…"
        case .starting: return "Starting…"
        case .transcribing: return "Transcribing…"
        case .polishing: return "Polishing…"
        }
    }

    // MARK: - notices

    private var hasNotices: Bool {
        if case .available = state.updateStatus { return true }
        if case .upgrading = state.updateStatus { return true }
        if case .downloading = state.polishDownload { return true }
        if case .downloading = state.speechDownload { return true }
        return state.microphoneDenied || state.lastCaptureSilent || !state.accessibilityTrusted
    }

    @ViewBuilder
    private var notices: some View {
        if state.microphoneDenied {
            NoticeRow(symbol: "mic.slash", tint: Theme.alert,
                      title: "Microphone access is off",
                      detail: "Murmur needs it to hear you.") {
                Button("Open Settings") { Self.openMicrophoneSettings() }
            }
        }
        if state.lastCaptureSilent {
            NoticeRow(symbol: "mic.slash", tint: Theme.caution,
                      title: "No sound from \(state.lastSilentDeviceName ?? "your microphone")",
                      detail: "That recording was silent. Pick another microphone in Settings.") {
                Button("Settings") { SettingsWindowController.show(appState: state) }
            }
        }
        if !state.accessibilityTrusted {
            NoticeRow(symbol: "hand.raised", tint: Theme.caution,
                      title: "Auto-paste is off",
                      detail: "Text goes to the clipboard until Murmur has Accessibility access.") {
                Button("Grant") {
                    _ = PasteService.isAccessibilityTrusted(prompt: true)
                    PasteService.openAccessibilitySettings()
                }
            }
        }
        downloadNotices
        updateNotice
    }

    @ViewBuilder
    private var downloadNotices: some View {
        if case .downloading(let fraction) = state.polishDownload {
            NoticeRow(symbol: "arrow.down.circle", tint: .secondary,
                      title: "Downloading local LLM model", progress: fraction) {
                Button("Show") {
                    SettingsWindowController.show(appState: state)
                    (NSApp.delegate as? AppDelegate)?.polishDownload.resurface()
                }
            }
        }
        if case .downloading(let model, let fraction) = state.speechDownload {
            let controller = (NSApp.delegate as? AppDelegate)?.speechDownload
            NoticeRow(symbol: "arrow.down.circle", tint: .secondary,
                      title: "Downloading \(SpeechModelCatalog.displayName(for: model))",
                      progress: fraction) {
                // A launch download has no sheet to re-open — omit "Show" for it.
                if controller?.canResurface ?? false {
                    Button("Show") {
                        SettingsWindowController.show(appState: state)
                        controller?.resurface()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var updateNotice: some View {
        switch state.updateStatus {
        case .available(let update):
            NoticeRow(symbol: "arrow.down.circle", tint: .accentColor,
                      title: "Murmur \(update.version) is available",
                      detail: state.installMethod.isBrew
                        ? "Installs quietly, then restarts Murmur."
                        : "Download the new version.") {
                Button(state.installMethod.isBrew ? "Upgrade" : "Download") {
                    guard let update = state.availableUpdate else { return }
                    UpgradeAction.run(release: update, installMethod: state.installMethod, appState: state)
                }
            }
        case .upgrading:
            NoticeRow(symbol: "arrow.triangle.2.circlepath", tint: .secondary,
                      title: "Installing update…",
                      detail: "Murmur restarts in about 30 seconds.") { EmptyView() }
        default:
            EmptyView()
        }
    }

    private static func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - transcript

    private func transcriptSection(_ transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.s8) {
                SectionHeader("Last transcript")
                Spacer()
                if let dur = state.lastAudioSeconds, let wall = state.lastWallSeconds {
                    let rtf = dur > 0 ? wall / dur : 0
                    Text(String(format: "%.1fs · %.2f×", dur, rtf))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(String(format: "%.1f seconds of audio, real-time factor %.2f", dur, rtf))
                }
                CopyTranscriptButton(text: transcript)
            }
            Text(transcript)
                .font(.system(size: 12))
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Components

/// The dictation shortcut, drawn like a key.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            )
            .accessibilityLabel("Shortcut \(text)")
    }
}

/// One compact notice: symbol, title, optional detail or progress, and an
/// optional small action on the right.
private struct NoticeRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var progress: Double? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: Theme.s8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let progress {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .accessibilityLabel("\(Int(progress * 100)) percent")
                }
            }
            Spacer(minLength: Theme.s4)
            accessory()
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

/// A menu-style row with the system's rounded hover highlight.
private struct MenuRow: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.1) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Copy-to-clipboard button (SPEC-020)

/// One-click copy of the last transcript. The icon flips to a checkmark for
/// 1.5s after a tap; tapping again before that resets the timer cleanly.
private struct CopyTranscriptButton: View {
    let text: String
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button(action: handleTap) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(copied ? "Copied" : "Copy transcript")
        .accessibilityLabel(copied ? "Transcript copied to clipboard" : "Copy transcript to clipboard")
    }

    private func handleTap() {
        PasteService.copyToClipboard(text)
        resetTask?.cancel()
        copied = true
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
