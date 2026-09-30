import AppKit
import AVFoundation
import SwiftUI
import Combine
import os
import ServiceManagement
import Sparkle
import UserNotifications
import MurmurKit
import MurmurDesign
import MurmurPlatform

//
// Pure AppKit entry. SwiftUI App protocol (Settings/WindowGroup) silently lost
// the menu-bar item on macOS 15 in our testing; NSApp.run() avoids the issue.

@main
struct MurmurApp {
    static func main() {
        // Must run before anything touches `Bundle.module` in SwiftPM
        // packages with resources. See BundleModuleFallback.swift.
        BundleModuleFallback.install()

        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

/// Shared history limit used by storage and the Settings picker.
/// `0` means no transcripts are saved; otherwise the newest entries are kept.
enum HistorySettings {
    static let maxEntriesKey = "historyMaxEntries"
    static let defaultMaxEntries = 50
    static var savedMaxEntries: Int {
        UserDefaults.standard.object(forKey: maxEntriesKey) as? Int ?? defaultMaxEntries
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var monitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // Defaults read from UserDefaults (Settings writes them via @AppStorage).
    private var defaultModel: String {
        UserDefaults.standard.string(forKey: "model") ?? "medium"
    }
    /// Use English as the initial transcription language.
    private var defaultLanguage: String? { "en" }
    private var selectedDictationMode: DictationMode {
        DictationMode.fromStored(UserDefaults.standard.string(forKey: "dictationMode"))
    }
    private var customWords: String? {
        UserDefaults.standard.string(forKey: "customWords")
    }
    private var soundsEnabled: Bool {
        UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true
    }
    private var vadEnabled: Bool {
        UserDefaults.standard.bool(forKey: "vadAutoStop")
    }
    private var vadSilenceSeconds: Double {
        let raw = UserDefaults.standard.double(forKey: "vadSilenceSeconds")
        return raw > 0 ? raw : 1.5
    }
    private var saveTranscripts: Bool {
        HistorySettings.savedMaxEntries > 0
    }
    private var saveAudio: Bool {
        UserDefaults.standard.bool(forKey: "saveAudio")
    }
    private var lastVoiceAt: Date?
    private static let voiceThreshold: Float = 0.06
    private static let vadMinDuration: Double = 0.8

    /// Indicates the recording was stopped by an audio-device change rather than
    /// by the user or voice activity detection. Reset at each new recording.
    private var recordingInterrupted = false
    private let appState = AppState()
    private let recorder = AudioRecorder()
    private let textInserter: any TextInserter = ClipboardPasteInserter()
    private let hotkey = HotkeyManager()
    private var rightOptionHeld = false
    private var rightOptionOwnsRecording = false
    private var rightOptionHoldGeneration = 0

    /// Owns polish-model downloads for the app lifetime, including while the
    /// Settings sheet is open. Connects download state to `appState`.
    @MainActor lazy var polishDownload = PolishModelDownloadController()
    /// Long-lived owner of the speech-model download (survives the Settings
    /// sheet). Wired to `appState` in didFinishLaunching.
    @MainActor lazy var speechDownload = SpeechModelDownloadController()
    private var transcriber: WhisperKitEngine?
    /// The model whose warm-path download a Settings download stood down, so a
    /// cancel can restart exactly that one and nothing else.
    private var displacedWarmModel: String?
    private var streamer: StreamingTranscriber?
    private var inlineStreamer: StreamingTranscriber?
    private var recordingStreamer: StreamingTranscriber?
    private var recordingDictationMode: DictationMode = .batch
    private var recordingOutputPlan: DictationOutputPlan = .pasteFinalTranscript
    private var inlineInsertTask: Task<Void, Never>?
    private var inlineInsertedAny = false
    private var overlayPreviewTask: Task<Void, Never>?
    /// Cancellable warm-up. Restarted (retargeted) when the user switches the
    /// active model while the launch download is still running.
    private var warmTask: Task<Void, Never>?
    /// Model the in-flight warm-up is for — guards against redundant restarts.
    private var warmingModel: String?
    /// A model swap requested mid-dictation, applied when we next go idle.
    private var pendingSwap = false
    // In-process polish engine stays warm across dictations: warmed on record-start,
    // then unloaded after polishIdleUnload with no dictation.
    private var polishEngine: LlamaCppPolishEngine?
    private var polishEngineModelPath: URL?
    private var polishIdleTimer: Timer?
    private var overlay: RecordingOverlay?
    private let updateChecker = UpdateChecker()
    let usageStats = UsageStats()
    let historyStore = HistoryStore(policy: .userConfigured(maxEntries: HistorySettings.savedMaxEntries))

    /// Sparkle updater initialized inside `applicationDidFinishLaunching` after
    /// install detection, so automatic-check settings are applied before its
    /// first scheduled poll. It stays alive for the app's full lifetime.
    /// The bundled SUPublicEDKey must be configured before Sparkle installs updates.
    var sparkleUpdater: SPUStandardUpdaterController?

    /// True when macOS revoked the login item while Murmur wasn't running.
    /// Settings reads this on appear to surface the approval hint.
    @MainActor var showsLaunchAtLoginApprovalHint: Bool = false

    private static let launchAtLoginLogger = Logger(
        subsystem: "com.jackammon.murmur",
        category: "LaunchAtLogin"
    )

    /// Live polish debug stream. Each run logs a JSON object with raw and
    /// polished text, engine, model, and duration. Output is not captured
    /// or persisted during normal use. Developers can tail formatted output
    /// with `bash scripts/debug-listen.sh polish`, or inspect it with `log stream`.
    private static let polishLog = Logger(
        subsystem: "com.jackammon.murmur",
        category: "polish"
    )

    /// Persist the last recording so the user can verify capture quality
    /// independent of model output. `open ~/Library/Application Support/Murmur/last-recording.wav`.
    private lazy var lastRecordingURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("last-recording.wav")
    }()

    private var elapsedTimer: Timer?
    private var permissionPollTimer: Timer?

    /// Spawning a `Task` per buffer doesn't guarantee FIFO at the actor;
    /// the AsyncStream pump does (yield is ordered, the consumer awaits one
    /// frame at a time).
    private var framesContinuation: AsyncStream<(samples: [Float], rate: Double)>.Continuation?
    private var framesPumpTask: Task<Void, Never>?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Arm the sentinel while this app session runs; a clean exit clears it.
        let priorSessionCrashed = checkAndMarkCrashSentinel()

        NSApp.setActivationPolicy(.accessory)
        appState.installMethod = InstallMethodDetector.detect()
        // The updater resolves its feed from this preference on each check.
        // No separate feed URL assignment is needed at launch.
        let persistedPrereleases = UserDefaults.standard.object(forKey: "receivePrereleases") as? Bool
        UserDefaults.standard.set(
            defaultReceivePrereleases(version: MurmurKit.version, persistedValue: persistedPrereleases),
            forKey: "receivePrereleases"
        )
        installStatusItem()
        installPopover()
        installHotkey()
        observePhaseForIcon()
        observeLevelsForIcon()
        observeColourThemeForDockIcon()
        overlay = RecordingOverlay(state: appState)

        // Connect download progress to AppState and resume interrupted downloads
        // from the previous launch.
        polishDownload.appState = appState
        polishDownload.reconcileOnLaunch()
        speechDownload.appState = appState
        // Hot-swap the live engine when a Settings download commits a new model.
        speechDownload.onCommitted = { [weak self] in
            self?.displacedWarmModel = nil
            self?.swapModel()
        }
        speechDownload.onWillDownload = { [weak self] in self?.cancelWarmDownload() }
        speechDownload.onCancelled = { [weak self] in self?.speechDownloadCancelled() }

        // Defensive: switching activation policy back to .accessory can hide
        // the menu-bar status item on macOS 15. Re-assert visibility on every
        // policy flip so the icon stays put after onboarding / Settings close.
        ActivationPolicy.afterChange = { [weak self] in
            self?.statusItem.isVisible = true
        }

        // Drive the overlay's level meter — pushes into a sliding window
        // so each bar represents a slice of recent audio rather than all
        // bars reacting to the same instantaneous RMS.
        recorder.levelHandler = { [weak self] level in
            Task { @MainActor in
                self?.appState.pushLevel(level)
            }
        }

        // If a device or route change stops the audio engine, the tap stops too and
        // the UI can freeze. Transcribe the partial recording and show a notice.
        // This callback runs on the main queue.
        recorder.interruptionHandler = { [weak self] in
            guard let self else { return }
            guard case .recording = self.appState.phase else { return }
            self.recordingInterrupted = true
            self.appState.lastNotice = "Recording interrupted by an audio device change"
            Diagnostics.shared.log(.recording, .warn, "interruption → auto-stopping mid-recording")
            self.stopAndTranscribe()
        }

        // Refresh permission state on launch and every 5 s while running so
        // the popover banner reflects reality even if the user grants AX
        // through System Settings without coming back to the app first.
        refreshPermissions()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }

        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasOnboarded {
            startWarm()
        } else {
            // First launch. Warm the transcriber the moment the onboarding's
            // model download finishes, not when the window closes — the demo
            // step lives inside that window and needs a live engine to
            // transcribe what the user dictates. onComplete is the safety net
            // for users who close the window before the install step.
            OnboardingWindowController.showIfFirstLaunch(
                appState: appState,
                polishDownload: polishDownload,
                onModelReady: { [weak self] in
                    Task { @MainActor in self?.startWarm() }
                },
                onComplete: { [weak self] in
                    Task { @MainActor in self?.startWarm() }
                }
            )
        }

        let history = historyStore
        Task { @MainActor in
            await history.enforceRetention()
            if priorSessionCrashed { await self.offerCrashBugReport() }
            await self.offerRecoveryIfNeeded()
        }

        // Keep the stored preference aligned if macOS approval was revoked while
        // Murmur was not running.
        reconcileLaunchAtLoginOnLaunch()
    }

    /// Reconcile the launch-at-login preference with macOS during startup.
    @MainActor
    private func reconcileLaunchAtLoginOnLaunch() {
        let desired = UserDefaults.standard.bool(forKey: "launchAtLogin")
        let action = reconcileLaunchAtLogin(
            desiredEnabled: desired,
            currentStatus: SMAppService.mainApp.status
        )
        switch action {
        case .noop:
            return
        case .register:
            do {
                try SMAppService.mainApp.register()
            } catch {
                // If macOS requires approval, keep the saved preference off.
                UserDefaults.standard.set(false, forKey: "launchAtLogin")
                showsLaunchAtLoginApprovalHint = true
                Self.launchAtLoginLogger.error("register() failed on launch: \(error.localizedDescription, privacy: .public)")
            }
        case .unregister:
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                Self.launchAtLoginLogger.error("unregister() failed on launch: \(error.localizedDescription, privacy: .public)")
            }
        case .resetToggleOff:
            UserDefaults.standard.set(false, forKey: "launchAtLogin")
            showsLaunchAtLoginApprovalHint = true
        }
    }

    /// macOS calls this when the user double-clicks the .app while it's
    /// already running. We're a menu-bar app with no main window, so the
    /// default behaviour is "nothing visible happens" — which makes users
    /// think the app is broken. Pop the menu so they can see we're alive.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        DispatchQueue.main.async { [weak self] in
            guard let self, let popover = self.popover, !popover.isShown else { return }
            self.togglePopover(nil)
        }
        return true
    }

    /// Forces the onboarding flow to re-appear. Called from Settings → About.
    @MainActor
    @objc func replayOnboarding() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        OnboardingWindowController.show(
            appState: appState,
            polishDownload: polishDownload,
            onModelReady: { [weak self] in
                Task { @MainActor in self?.startWarm() }
            },
            onComplete: { [weak self] in
                Task { @MainActor in self?.startWarm() }
            }
        )
    }

    /// Manual update check, called from Settings → About → "Check for updates".
    @MainActor
    @objc func checkForUpdatesManually() {
        Task { await pollForUpdate(force: true) }
    }

    /// Brew cask and Sparkle must not manage the same app bundle. Sparkle
    /// remains available for manual checks, while scheduled checks are
    /// disabled for Homebrew installs. The popover remains the primary
    /// update surface. Configure `SUPublicEDKey` before shipping updates.
    @MainActor
    private func installSparkleUpdater() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        switch appState.installMethod {
        case .homebrew:
            // Brew owns the bundle. Keep manual update checks available
            // and mute Sparkle's scheduled checks.
            controller.updater.automaticallyChecksForUpdates = false
        case .manual:
            // DMG / drag-installed. Let Sparkle's daily scheduler run;
            // the interval is governed by `SUScheduledCheckInterval` in
            // the bundled Info.plist.
            controller.updater.automaticallyChecksForUpdates = true
        }
        sparkleUpdater = controller
    }

    private func pollForUpdate(force: Bool = false) async {
        if !force, let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        await MainActor.run { appState.updateStatus = .checking }
        do {
            let release = try await updateChecker.checkForUpdate(currentVersion: MurmurKit.version)
            let now = Date()
            await MainActor.run {
                if let release {
                    appState.updateStatus = .available(release)
                } else {
                    appState.updateStatus = .upToDate(version: MurmurKit.version, at: now)
                }
            }
            UserDefaults.standard.set(now, forKey: "lastUpdateCheck")
        } catch UpdateChecker.Error.noReleases {
            // Repo has no releases at all — uncommon, but treat as
            // up-to-date rather than an error so manual checks don't
            // surface a scary message during pre-release windows.
            await MainActor.run {
                appState.updateStatus = .upToDate(version: MurmurKit.version, at: Date())
            }
        } catch {
            await MainActor.run { appState.updateStatus = .failed("\(error)") }
        }
    }

    // MARK: - status item + popover

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Phase-driven glyph is set in `updateIcon`; seed with the resting
        // mark so the status item renders on first paint.
        statusItem.button?.image = StatusGlyph.image(.rest)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Murmur"
        statusItem.button?.setAccessibilityLabel("Murmur")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func installPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContent(state: appState)
        )
    }

    @MainActor
    @objc func togglePopover(_ sender: AnyObject?) {
        // Route right-click to a small context menu (Show app, Quit). Left
        // click toggles the popover with live state.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.type == .rightMouseDown {
            showStatusItemMenu()
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            stopMonitoringClicksOutside()
        } else {
            // Refresh now so the AX banner reflects the latest state immediately
            // when the popover opens.
            refreshPermissions()
            // Size the popover to its SwiftUI content *before* showing it: the
            // arrow notch is drawn against the geometry at placement time, so a
            // window that resizes afterwards leaves the arrow pointing wide of
            // the status item.
            if let content = popover.contentViewController?.view {
                content.layoutSubtreeIfNeeded()
                let fitting = content.fittingSize
                if fitting.width > 0, fitting.height > 0 { popover.contentSize = fitting }
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            monitorClicksOutside()
        }
    }

    /// Right-click menu for opening the app, sending feedback, or quitting.
    /// Settings remains in the popover, and feedback opens GitHub.
    @MainActor
    private func showStatusItemMenu() {
        let menu = NSMenu()

        let show = NSMenuItem(title: "Show app", action: #selector(menuShowApp), keyEquivalent: ",")
        show.target = self
        menu.addItem(show)

        let feedback = NSMenuItem(title: "Send feedback…", action: #selector(menuSendFeedback), keyEquivalent: "")
        feedback.target = self
        menu.addItem(feedback)

        let faq = NSMenuItem(title: "FAQ / Help…", action: #selector(menuOpenFAQ), keyEquivalent: "")
        faq.target = self
        menu.addItem(faq)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Murmur", action: #selector(menuQuitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attach the menu, fire a synthetic click so AppKit shows it
        // anchored to the status-item button, then detach so the next
        // click routes back to `togglePopover`.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @MainActor
    @objc private func menuShowApp() {
        SettingsWindowController.show(appState: appState)
    }

    @MainActor
    @objc private func menuSendFeedback() {
        // The user can add a description in GitHub's issue form; Murmur does
        // not submit diagnostics or transcript data.
        writeDiagnosticsFileAndReveal()
        guard let url = URL(string: "https://github.com/jackammon/murmur/issues/new/choose") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Opens the README troubleshooting section in the default browser.
    @MainActor
    @objc private func menuOpenFAQ() {
        guard let url = URL(string: "https://github.com/jackammon/murmur#troubleshooting") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    @objc private func menuQuitApp() {
        NSApplication.shared.terminate(nil)
    }

    @MainActor
    func popoverToggleRecording() {
        // Return focus to the previous app before capture or paste. The
        // user can reopen the popover to stop a recording from here.
        popover.performClose(nil)
        stopMonitoringClicksOutside()
        toggleRecording()
    }

    /// The Overlay card's Stop button. Only stops; never starts a recording.
    @MainActor
    func overlayStopRecording() {
        guard case .recording = appState.phase else { return }
        toggleRecording()
    }

    @MainActor
    func popoverShowSettings() {
        popover.performClose(nil)
        stopMonitoringClicksOutside()
        menuShowApp()
    }

    @MainActor
    func popoverQuitApp() {
        menuQuitApp()
    }

    @MainActor
    private func refreshPermissions() {
        let trusted = PasteService.isAccessibilityTrusted()
        if appState.accessibilityTrusted != trusted {
            appState.accessibilityTrusted = trusted
        }
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let micDenied = mic == .denied || mic == .restricted
        if appState.microphoneDenied != micDenied {
            appState.microphoneDenied = micDenied
        }
    }

    private func monitorClicksOutside() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.stopMonitoringClicksOutside()
        }
    }

    private func stopMonitoringClicksOutside() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    // MARK: - icon ↔ phase

    private func observePhaseForIcon() {
        // Icon depends on phase + whether an update is available, so observe
        // both. CombineLatest republishes whenever either side changes.
        appState.$phase
            .combineLatest(appState.$updateStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase, status in
                self?.updateIcon(for: phase, hasUpdate: status.hasAvailableUpdate)
                Task { @MainActor in self?.applyPendingSwapIfIdle() }
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for phase: AppState.Phase, hasUpdate: Bool) {
        guard let button = statusItem.button else { return }
        button.image = Self.statusGlyph(for: phase, levels: appState.levelHistory, hasUpdate: hasUpdate)
        button.imagePosition = .imageOnly
        button.title = ""
        let label = Self.statusLabel(for: phase, hasUpdate: hasUpdate)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    /// The Dock icon follows the Colour setting while Murmur runs; Off
    /// restores the bundle's Paper icon.
    private func observeColourThemeForDockIcon() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in DockIcon.current }
            .prepend(DockIcon.current)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { theme in
                Task { @MainActor in DockIcon.apply(theme) }
            }
            .store(in: &cancellables)
    }

    /// While recording, the menu-bar glyph follows the microphone level.
    /// Throttled: the glyph is tiny and a redraw per audio buffer buys nothing.
    private func observeLevelsForIcon() {
        appState.$levelHistory
            .throttle(for: .milliseconds(80), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] levels in
                guard let self, case .recording = self.appState.phase,
                      let button = self.statusItem.button else { return }
                button.image = Self.statusGlyph(for: .recording, levels: levels,
                                                hasUpdate: self.appState.updateStatus.hasAvailableUpdate)
            }
            .store(in: &cancellables)
    }

    private static func statusGlyph(for phase: AppState.Phase, levels: [Float], hasUpdate: Bool) -> NSImage {
        switch phase {
        case .warming:
            return StatusGlyph.image(.dimmed, badge: hasUpdate)
        case .idle, .ready:
            return StatusGlyph.image(.rest, badge: hasUpdate)
        case .starting, .recording:
            return StatusGlyph.image(.listening(levels), badge: hasUpdate)
        case .transcribing, .polishing:
            return StatusGlyph.image(.dimmed, badge: hasUpdate)
        case .error:
            return StatusGlyph.image(.alert, badge: hasUpdate)
        }
    }

    private static func statusLabel(for phase: AppState.Phase, hasUpdate: Bool) -> String {
        let status: String
        switch phase {
        case .warming:      status = "Loading model"
        case .idle, .ready: status = "Ready"
        case .starting:     status = "Starting"
        case .recording:    status = "Listening"
        case .transcribing: status = "Transcribing"
        case .polishing:    status = "Polishing"
        case .error:        status = "Dictation failed"
        }
        return hasUpdate ? "Murmur — \(status), update available" : "Murmur — \(status)"
    }

    // MARK: - hotkey

    private func installHotkey() {
        hotkey.registerToggle { [weak self] in self?.toggleRecording() }
        hotkey.registerFunctionKeyToggle { [weak self] in self?.toggleRecording() }
        hotkey.registerRightOptionHold(
            onKeyDown: { [weak self] in self?.rightOptionDown() },
            onKeyUp: { [weak self] in self?.rightOptionUp() }
        )
    }

    @MainActor
    func setRightOptionHoldEnabled(_ enabled: Bool) {
        hotkey.setRightOptionHoldEnabled(enabled)
    }

    @MainActor
    private func rightOptionDown() {
        guard !rightOptionHeld else { return }
        rightOptionHeld = true
        switch appState.phase {
        case .idle, .ready, .error:
            guard localEngineReady() else { return }
            rightOptionOwnsRecording = true
            rightOptionHoldGeneration += 1
            appState.recordingMode = .dictation
            appState.phase = .starting
            startRecording(holdGeneration: rightOptionHoldGeneration)
        default:
            // A toggle recording keeps its owner.
            break
        }
    }

    @MainActor
    private func rightOptionUp() {
        guard rightOptionHeld else { return }
        rightOptionHeld = false
        rightOptionHoldGeneration += 1
        guard rightOptionOwnsRecording else { return }
        rightOptionOwnsRecording = false
        if appState.phase == .recording { stopAndTranscribe() }
    }

    @MainActor
    private func releaseRightOptionOwnershipOnFailure(_ holdGeneration: Int?) {
        guard let holdGeneration, holdGeneration == rightOptionHoldGeneration else { return }
        rightOptionOwnsRecording = false
    }

    @MainActor
    private func toggleRecording() {
        switch appState.phase {
        case .idle, .ready, .error:
            guard localEngineReady() else { return }
            appState.recordingMode = .dictation
            startRecording()
        case .recording:
            rightOptionOwnsRecording = false
            stopAndTranscribe()
        case .warming, .starting, .transcribing, .polishing:
            // Ignore — the user gets a hotkey-tap during a transition; we just drop it.
            NSSound.beep()
        }
    }

    /// A local dictation started with no engine loaded records happily and then
    /// throws the utterance away at the nil-engine guard in `stopAndTranscribe`.
    /// Refuse up front instead: the model is downloading, or waiting on the
    /// Settings download sheet, and the user should hear about it before they
    /// speak. `.warming` already beeps in the callers, so this only covers the
    /// idle-but-engineless window a Settings download opens.
    @MainActor
    private func localEngineReady() -> Bool {
        if transcriber != nil { return true }
        NSSound.beep()
        appState.phase = .error("Speech model isn't ready yet — finish the download in Settings.")
        return false
    }

    // MARK: - record → transcribe pipeline

    /// The polish engine configured for the current dictation. Single source
    /// for both engine construction and the live overlay's "will it polish?"
    /// decision.
    private var polishEngineKind: PolishEngineKind {
        PolishEngineKind(rawValue: UserDefaults.standard.string(forKey: "polishEngine") ?? "off") ?? .off
    }

    /// Runs optional LLM polish and regex cleanup on a transcript using the
    /// current settings. Shared by live dictation and crash recovery.
    private func polishedTranscript(from transcript: String) async -> PolishResult {
        let polishEnabled = UserDefaults.standard.object(forKey: "polishText") as? Bool ?? true
        let engineKind = polishEngineKind
        let engine: TextPolishEngine?
        switch engineKind {
        case .off:
            engine = nil
        case .llamaCpp:
            engine = await MainActor.run { self.retainedLlamaEngine(path: PolishModelCatalog.localURL) }
        }
        // Custom polish instructions. Read fresh
        // each dictation; blank/absent falls back to the shipped default.
        let custom = UserDefaults.standard.string(forKey: "polishSystemPrompt")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let systemInstructions = (custom?.isEmpty ?? true) ? nil : custom
        let result = await PolishPipeline.polish(
            transcript,
            engine: engine,
            regexEnabled: polishEnabled,
            context: PolishContext(language: defaultLanguage, timestamp: Date(),
                                   systemInstructions: systemInstructions)
        )
        var record: [String: Any] = [
            "raw": transcript,
            "polished": result.text,
            "engine": engineKind.rawValue,
            "llm": result.llmSucceeded,
            // Confirms which polish prompt was live: "default" or "custom(<n>c)".
            "prompt": systemInstructions.map { "custom(\($0.count)c)" } ?? "default",
        ]
        if let ms = result.llmMillis { record["ms"] = ms }
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            Self.polishLog.debug("\(json, privacy: .public)")
        }
        return result
    }

    private func startRecording(holdGeneration: Int? = nil) {
        recordingDictationMode = selectedDictationMode
        let autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
        recordingOutputPlan = recordingDictationMode.outputPlan(autoPasteEnabled: autoPasteEnabled)
        recordingStreamer = recordingDictationMode == .inline ? inlineStreamer : streamer
        appState.activeDictationMode = recordingDictationMode
        appState.livePreview = ""
        // Claim the lifecycle before an async permission prompt. Otherwise a
        // second hotkey press can start a competing recording and overwrite
        // this session's mode and streamer snapshot.
        appState.phase = .starting
        Task {
            if recordingOutputPlan == .insertFinalizedChunks && !PasteService.isAccessibilityTrusted() {
                releaseRightOptionOwnershipOnFailure(holdGeneration)
                appState.phase = .error("Inline mode needs Accessibility permission to paste each phrase. Grant it in System Settings.")
                return
            }
            guard await AudioRecorder.requestPermission() else {
                await MainActor.run {
                    releaseRightOptionOwnershipOnFailure(holdGeneration)
                    appState.phase = .error("Microphone permission denied. Enable in System Settings → Privacy & Security → Microphone.")
                }
                return
            }
            if let holdGeneration, holdGeneration != rightOptionHoldGeneration {
                appState.phase = .idle
                return
            }
            await MainActor.run {
                appState.phase = .starting
                cancelPolishIdleUnload()
                warmPolishEngineIfNeeded()
            }

            // Connect captured audio to the streamer even for short utterances;
            // stopAndTranscribe selects the streaming or batch path. If the
            // engine is not warm, framesHandler stays nil.
            let language = defaultLanguage
            let words = customWords
            await tearDownFramesPump()
            if let streamer = recordingStreamer {
                // Pump pattern: the audio thread `yield`s into an unbounded
                // AsyncStream; a single Task drains it serially into the
                // actor. This preserves FIFO order — `Task { await ... }` per
                // buffer would race because actor reentry isn't queued in
                // submission order.
                //
                // `.unbounded` is safe: the pump consumer just hops into the
                // actor (sub-ms) per buffer, and producer rate is ~50/s of
                // ~10 ms buffers. The actor itself only retains samples until
                // the next emitChunksIfReady cut, so steady-state memory is
                // bounded by maxChunkSeconds, not stream backlog.
                let (stream, continuation) = AsyncStream<(samples: [Float], rate: Double)>.makeStream(
                    bufferingPolicy: .unbounded
                )
                self.framesContinuation = continuation
                recorder.framesHandler = { samples, rate in
                    continuation.yield((samples, rate))
                }
                self.framesPumpTask = Task { [weak streamer] in
                    for await frame in stream {
                        await streamer?.appendFrames(frame.samples, sampleRate: frame.rate)
                    }
                }
                await streamer.begin(language: language, customWords: words)
                if recordingOutputPlan == .insertFinalizedChunks {
                    let chunks = await streamer.finalizedChunks()
                    await MainActor.run {
                        PasteService.beginSequentialSession()
                        inlineInsertedAny = false
                    }
                    inlineInsertTask = Task { @MainActor [weak self] in
                        for await chunk in chunks {
                            guard let self else { break }
                            let phrase = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard chunk.succeeded, chunk.hasSpeechEnergy, !phrase.isEmpty
                            else { continue }
                            guard await self.textInserter.insertOrdered(phrase + " ") else { break }
                            self.inlineInsertedAny = true
                        }
                    }
                } else if recordingDictationMode == .overlay {
                    let previews = await streamer.partialPreview()
                    overlayPreviewTask = Task { @MainActor [weak self] in
                        for await preview in previews {
                            guard let self else { break }
                            self.appState.livePreview = preview
                        }
                    }
                }
            } else {
                recorder.framesHandler = nil
            }

            if let holdGeneration, holdGeneration != rightOptionHoldGeneration {
                await tearDownFramesPump()
                if let streamer = recordingStreamer { await streamer.cancel() }
                await finishInlineInsertion()
                await finishOverlayPreview()
                appState.phase = .idle
                return
            }

            do {
                let inputUID = UserDefaults.standard.string(forKey: "inputDeviceUID")
                _ = try recorder.start(outputURL: lastRecordingURL, inputDeviceUID: inputUID)
                await MainActor.run {
                    appState.phase = .recording
                    appState.elapsedSeconds = 0
                    appState.resetLevels()
                    appState.lastNotice = nil
                    recordingInterrupted = false
                    lastVoiceAt = nil
                    startElapsedTimer()
                    playSound("Tink")
                }
                if let holdGeneration, holdGeneration != rightOptionHoldGeneration,
                   appState.phase == .recording {
                    stopAndTranscribe()
                }
            } catch {
                await tearDownFramesPump()
                if let streamer = recordingStreamer { await streamer.cancel() }
                await finishInlineInsertion()
                await finishOverlayPreview()
                await MainActor.run {
                    releaseRightOptionOwnershipOnFailure(holdGeneration)
                    appState.phase = .error("Recording failed: \(error)")
                    schedulePolishIdleUnload()
                }
            }
        }
    }

    /// Hold the transcribing phase for at least this long. Short utterances
    /// otherwise transcribe in <300 ms — the progress bar flashes 0→100→done
    /// faster than the eye can register, which defeats the point of having
    /// progress UI in the first place.
    private static let minTranscribeDwell: TimeInterval = 0.6
    private static let polishIdleUnload: TimeInterval = 300   // 5 min
    /// Use streaming for recordings at or above this duration; shorter clips
    /// use the faster batch path. This matches the streaming engine setting.
    private static let streamingThreshold: TimeInterval = 30

    /// Display name of the input device the next recording will use: the
    /// user's picked device, or the system default. Used in the silent-capture
    /// banner/notification copy.
    private static func currentInputDeviceName(uid: String?) -> String {
        if let uid, !uid.isEmpty,
           let match = AudioInputDevices.list().first(where: { $0.uid == uid }) {
            return match.name
        }
        return "the system default microphone"
    }

    /// Notify the user about a silent recording even when the popover is closed.
    /// Best-effort; this silently does nothing if notifications are denied.
    private static func postSilentCaptureNotification(deviceName: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "No sound detected"
            content.body = "Murmur heard nothing from \(deviceName). Open Murmur to switch microphones."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "murmur.capture.silent",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func stopAndTranscribe() {
        stopElapsedTimer()
        let audioDuration = recorder.elapsedSeconds
        // Captured peak level, read before stop() tears the recorder down.
        // A silent capture (dead/muted mic, or a virtual input device that
        // emits silence) otherwise gets transcribed into a Whisper
        // hallucination like "You." — warn the user instead.
        let capturePeakRMS = recorder.peakRMS
        // The device actually captured from (may be the system-default fallback,
        // not the saved preference). Read before stop() tears the recorder down.
        let activeDeviceUID = recorder.activeInputDeviceUID
        guard let url = recorder.stop() else {
            Task {
                await tearDownFramesPump()
                if let streamer = recordingStreamer { await streamer.cancel() }
                await finishInlineInsertion()
                await finishOverlayPreview()
                appState.phase = .error("Recording stopped without an audio file.")
            }
            return
        }

        if capturePeakRMS < AudioRecorder.silenceRMSThreshold {
            let deviceName = Self.currentInputDeviceName(uid: activeDeviceUID)
            Task {
                await tearDownFramesPump()
                if let streamer = recordingStreamer { await streamer.cancel() }
                await finishInlineInsertion()
                await finishOverlayPreview()
                await MainActor.run {
                    appState.phase = .error("No sound detected. Pick your microphone in Settings → General, or check System Settings → Sound → Input.")
                    appState.lastCaptureSilent = true
                    appState.lastSilentDeviceName = deviceName
                    schedulePolishIdleUnload()
                }
                Self.postSilentCaptureNotification(deviceName: deviceName)
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        Task {
            let phaseStart = Date()
            await MainActor.run {
                appState.phase = .transcribing
                appState.transcriptionProgress = 0
                appState.lastCaptureSilent = false   // a non-silent capture clears the warning
            }

            if transcriber == nil {
                await tearDownFramesPump()
                if let streamer = recordingStreamer { await streamer.cancel() }
                await finishInlineInsertion()
                await finishOverlayPreview()
                await MainActor.run {
                    appState.phase = .error("Still getting ready — try again in a moment.")
                }
                try? FileManager.default.removeItem(at: url)
                return
            }

            // Drive the progress bar from a linear ramp tied to audio length
            // rather than WhisperKit's own Progress object. The KVO progress
            // reports unevenly — slow start then a snap to 100% at the end —
            // which felt broken to the user. A smooth ramp from 0 → ~95% over
            // the expected wall-clock (audio × 0.25, conservative for medium
            // on M-series) reads as real progress; we snap to 100% on actual
            // completion below.
            let estimatedTranscribe = max(0.4, audioDuration * 0.25)
            let progressTask = Task<Void, Never> { [weak self] in
                let start = Date()
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    let frac = min(0.95, elapsed / estimatedTranscribe)
                    await MainActor.run { self?.appState.transcriptionProgress = frac }
                    if frac >= 0.95 { break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            defer { progressTask.cancel() }

            do {
                // Streaming reuses chunks transcribed during recording, so the
                // post-stop wait stays roughly flat as utterance length grows.
                // Teardown drains the audio-thread pump first so finish()
                // sees every frame; cancel() is fine to call after teardown
                // (any frames still queued become a no-op once cancelled).
                let transcribeStart = Date()
                let result: EngineTranscription
                let pathLabel: String
                var chunkCount: Int?
                var chunkFailures: Int?
                if (recordingDictationMode.streamsFromStart || audioDuration >= Self.streamingThreshold),
                          let streamer = recordingStreamer {
                    await tearDownFramesPump()
                    let r = try await streamer.finish()
                    await finishInlineInsertion()
                    await finishOverlayPreview()
                    chunkCount = r.chunkCount
                    chunkFailures = r.chunkFailures
                    pathLabel = "streaming"
                    result = EngineTranscription(
                        text: r.text,
                        detectedLanguage: r.detectedLanguage,
                        audioSeconds: r.audioSeconds > 0 ? r.audioSeconds : audioDuration,
                        wallSeconds: r.wallSeconds,
                        timeToFirstToken: nil
                    )
                } else {
                    await tearDownFramesPump()
                    if let streamer = recordingStreamer { await streamer.cancel() }
                    await finishInlineInsertion()
                    await finishOverlayPreview()
                    pathLabel = "offline"
                    guard let engine = transcriber else {
                        throw EngineError.runtimeFailed("Speech model isn't loaded yet")
                    }
                    result = try await engine.transcribe(
                        audioFile: url,
                        language: defaultLanguage,
                        customWords: customWords
                    )
                }
                let transcribeWall = Date().timeIntervalSince(transcribeStart)

                // The captured frame count survives `stop()` and resets at the
                // next start. A large wall-time gap indicates the tap stopped
                // during this recording.
                let captured = recorder.capturedSeconds
                let health = RecordingHealth.assess(wallSeconds: audioDuration, capturedSeconds: captured)
                let diag = DiagnosticsReport.LastRecording(
                    wallSeconds: audioDuration,
                    capturedSeconds: captured,
                    health: health,
                    path: pathLabel,
                    chunkCount: chunkCount,
                    chunkFailures: chunkFailures,
                    transcribeWallSeconds: result.wallSeconds,
                    audioSeconds: result.audioSeconds,
                    detectedLanguage: result.detectedLanguage,
                    interrupted: recordingInterrupted
                )
                lastRecordingDiag = diag
                // Settings → Stats → "Recording health" (opt-in display).
                await MainActor.run { appState.pushRecentRecording(diag) }
                let rtfText = DiagnosticsReport.rtf(transcribe: result.wallSeconds, audio: result.audioSeconds)
                    .map { String(format: "%.2f", $0) } ?? "-"
                Diagnostics.shared.log(
                    .transcription,
                    health.isIncomplete ? .error : .info,
                    "stop: wall \(String(format: "%.1f", audioDuration))s captured \(String(format: "%.1f", captured))s"
                    + " \(pathLabel) rtf=\(rtfText) lang=\(result.detectedLanguage ?? "-")"
                    + (health.isIncomplete ? " ⚠ INCOMPLETE" : "")
                    + (recordingInterrupted ? " (interrupted)" : "")
                )


                if polishEngineKind != .off {
                    await MainActor.run { appState.phase = .polishing }
                }
                let polishStart = Date()
                let polished = (await polishedTranscript(from: result.text)).text
                let polishWall = Date().timeIntervalSince(polishStart)

                // Hold the progress bar at full briefly so the user sees the
                // transition land instead of jumping straight to "Pasted".
                await MainActor.run {
                    appState.transcriptionProgress = 1.0
                }
                let elapsed = Date().timeIntervalSince(phaseStart)
                if elapsed < Self.minTranscribeDwell {
                    let remaining = Self.minTranscribeDwell - elapsed
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }

                // Post-stop wait breakdown, so a "thinking" stall pins to a step.
                // `stall` = seconds the bar sat at 95% (transcribe ran past the
                // ramp estimate); transcribe−engine is drain/teardown overhead.
                let stall = max(0, transcribeWall - estimatedTranscribe)
                Diagnostics.shared.log(
                    .transcription, .info,
                    "timing: est=\(String(format: "%.2f", estimatedTranscribe))s"
                    + " transcribe=\(String(format: "%.2f", transcribeWall))s"
                    + " engine=\(String(format: "%.2f", result.wallSeconds))s"
                    + " stall=\(String(format: "%.2f", stall))s"
                    + " polish=\(String(format: "%.2f", polishWall))s \(pathLabel)"
                )

                let pasted: Bool
                switch recordingOutputPlan {
                case .insertFinalizedChunks:
                    pasted = inlineInsertedAny
                case .pasteFinalTranscript:
                    pasted = textInserter.insert(polished)
                case .copyFinalTranscript:
                    PasteService.copyToClipboard(polished)
                    pasted = false
                }

                await MainActor.run {
                    appState.lastTranscript = polished
                    appState.lastAudioSeconds = result.audioSeconds
                    appState.lastWallSeconds = result.wallSeconds
                    appState.lastRecordingURL = url
                    appState.lastPasted = pasted
                    appState.accessibilityTrusted = PasteService.isAccessibilityTrusted()
                    appState.phase = .ready
                    playSound("Pop")
                    schedulePolishIdleUnload()
                }

                // A history or stats failure must not undo the paste above.
                let detectedLanguage = result.detectedLanguage
                let modelLabel = self.defaultModel
                let audioDuration = result.audioSeconds
                let saveTranscriptsFlag = self.saveTranscripts
                let saveAudioFlag = self.saveAudio
                let stats = self.usageStats
                let history = self.historyStore
                Task {
                    await stats.record(transcript: polished, audioSeconds: audioDuration)
                    if saveTranscriptsFlag {
                        let audio = saveAudioFlag ? Self.loadAudioSamples(from: url) : nil
                        _ = try? await history.save(
                            audio: audio?.samples,
                            audioSampleRate: audio?.sampleRate ?? 16_000,
                            transcript: polished,
                            language: detectedLanguage,
                            modelID: modelLabel,
                            durationSeconds: audioDuration
                        )
                    }
                }
            } catch {
                if let streamer = recordingStreamer { await streamer.cancel() }
                await finishInlineInsertion()
                await finishOverlayPreview()
                // Diagnostics persist locally and may be exported, so keep only
                // the first error line; implementation details can be multiline.
                let firstLine = "\(error)".components(separatedBy: "\n")[0]
                Diagnostics.shared.log(.transcription, .error, "transcribe failed: \(firstLine)")
                await MainActor.run {
                    appState.phase = .error(DictationFailure.message(for: error))
                    schedulePolishIdleUnload()
                }
            }
            // Recording is kept for inspection — we let the next start() overwrite it.
        }
    }

    /// Start (or restart) warm-up for the current `defaultModel`. Restarting
    /// cancels an in-flight warm download and re-aims at the new model — this is
    /// how a model switch during launch warm-up retargets without spawning a
    /// second concurrent download. Idempotent for the same model.
    @MainActor
    func startWarm(force: Bool = false) {
        if !force, transcriber != nil { return }
        // Never stomp a live dictation's phase.
        if isDictating { pendingSwap = true; return }
        let model = defaultModel
        if !force, warmingModel == model { return }   // already warming this one
        warmTask?.cancel()
        warmingModel = model
        warmTask = Task { [weak self] in
            await self?.warmBody(model: model, force: force)
            await MainActor.run { if self?.warmingModel == model { self?.warmingModel = nil } }
        }
    }

    /// True while a dictation is in flight — we never swap the engine under it.
    @MainActor private var isDictating: Bool { appState.isDictating }

    /// Hot-swap the live engine to the current `defaultModel`. Cold start →
    /// normal warm-up; already running it → no-op; mid-dictation → deferred
    /// until the dictation finishes (see `applyPendingSwapIfIdle`).
    @MainActor
    func swapModel() {
        let target = defaultModel
        guard transcriber != nil else { startWarm(); return }
        guard transcriber?.modelID != target else { return }
        if isDictating { pendingSwap = true; return }
        pendingSwap = false
        startWarm(force: true)
    }

    /// A Settings download was cancelled (or dismissed after failing). Put back
    /// only the warm-up this download displaced — the user cancelled *their*
    /// transfer, not the one we stood down behind their back. With nothing
    /// displaced the app stays engineless on purpose: restarting the warm path
    /// would re-fetch the gigabytes they just refused (or try to load a torn
    /// cache), and Settings offers the download again instead.
    @MainActor
    func speechDownloadCancelled() {
        guard let displaced = displacedWarmModel else { return }
        displacedWarmModel = nil
        guard displaced == defaultModel else { return }
        startWarm()
    }

    /// Stop a warm-path download so the Settings sheet can own the transfer —
    /// two multi-gigabyte fetches must never run at once. Only the download
    /// phase is interruptible; once the engine is loading there's nothing large
    /// left to stop, and nothing to put back.
    @MainActor
    func cancelWarmDownload() {
        guard case .downloading(let model, _) = appState.speechDownload else { return }
        displacedWarmModel = model
        warmTask?.cancel()
        warmingModel = nil
        appState.speechDownload = .inactive
        if case .warming = appState.phase { appState.phase = .idle }
    }

    /// Phase-observer hook: apply a deferred swap once dictation ends.
    @MainActor
    func applyPendingSwapIfIdle() {
        guard pendingSwap, !isDictating else { return }
        pendingSwap = false
        startWarm(force: true)
    }

    private func warmBody(model: String, force: Bool = false) async {
        if !force, self.transcriber != nil { return }
        // A canceled warm-up may already have returned the UI to idle; leave it there.
        if Task.isCancelled { return }
        await MainActor.run {
            appState.phase = .warming(modelLabel: model)
            // Clear any banner left by a just-retargeted warm-up so it doesn't
            // briefly show the old model while this one prepares.
            appState.speechDownload = .inactive
        }
        do {
            // If the weights aren't on disk yet, download them with a visible
            // menu-bar progress banner instead of a silent blocking fetch inside
            // the engine init. No sheet — this isn't user-initiated. (A missing
            // tokenizer alone isn't worth a banner; the engine init fetches it.)
            if !WhisperKitEngine.hasModelWeights(for: model) {
                await MainActor.run { appState.speechDownload = .downloading(model: model, fraction: 0) }
                try await WhisperKitEngine.ensureDownloaded(model: model) { fraction in
                    // Guard against a late tick from a just-cancelled (retargeted)
                    // download flicking the banner back to the old model.
                    Task { @MainActor in
                        if self.warmingModel == model {
                            self.appState.speechDownload = .downloading(model: model, fraction: fraction)
                        }
                    }
                }
                await MainActor.run { appState.speechDownload = .inactive }
            }
            // A retarget may have landed in the gap between file downloads (where
            // the snapshot returns without throwing) — bail before loading the
            // now-stale model so the new warm-up wins.
            try Task.checkCancellation()
            let engine = try await WhisperKitEngine(model: model)
            // Swap atomically on the main actor so a dictation can't start
            // between the busy-check and the assignment. If a force-reload's
            // load window overlapped a dictation, don't swap under it — defer to
            // idle. (A large model briefly holds old + new engine in memory here.)
            let swapped = await MainActor.run { () -> Bool in
                // Drop this loaded engine if its warm-up task was canceled.
                if Task.isCancelled { return false }
                // A dictation started during the load window: don't swap under it.
                // We discard this just-loaded engine and re-load on idle rather
                // than stash it — keeps the swap state machine to one in-flight
                // model. Costs one extra load only in the rare switch-then-
                // immediately-dictate race; not worth more state to optimise.
                if force, self.isDictating { self.pendingSwap = true; return false }
                self.transcriber = engine
                self.streamer = engine.makeStreamingTranscriber()
                self.inlineStreamer = engine.makeStreamingTranscriber(config: .init(
                    streamingThreshold: 0,
                    targetChunkSeconds: 3,
                    maxChunkSeconds: 10
                ))
                appState.speechDownload = .inactive
                appState.phase = .idle
                appState.modelLabel = model
                return true
            }
            guard swapped else { return }
        } catch {
            // A retarget cancels this task; let the new warm take over silently.
            if Task.isCancelled || error is CancellationError { return }
            await MainActor.run {
                appState.speechDownload = .inactive
                appState.phase = .error("Failed to load Whisper: \(error)")
            }
        }
    }


    /// Retained engine for the configured path; rebuilds if absent or path changed.
    @MainActor
    private func retainedLlamaEngine(path: URL) -> LlamaCppPolishEngine {
        if let engine = polishEngine, polishEngineModelPath == path {
            return engine
        }
        unloadPolishEngine()
        let engine = LlamaCppPolishEngine(modelPath: path)
        polishEngine = engine
        polishEngineModelPath = path
        return engine
    }

    /// Record-start hook: drop the engine if the user switched away from llamaCpp,
    /// else retain one and load it in the background so the ~3 GB load hides behind
    /// the record+transcribe window.
    @MainActor
    private func warmPolishEngineIfNeeded() {
        guard polishEngineKind == .llamaCpp else {
            unloadPolishEngine()
            return
        }
        let engine = retainedLlamaEngine(path: PolishModelCatalog.localURL)
        Task { try? await engine.warm() }
    }

    @MainActor
    private func unloadPolishEngine() {
        guard let engine = polishEngine else { return }
        polishEngine = nil
        polishEngineModelPath = nil
        Task.detached { await engine.unload() }
    }

    /// Unload the polish model and remove its local file. Unloading first frees
    /// memory because a loaded engine can keep the file mapped.
    @MainActor
    func deletePolishModel() {
        UserDefaults.standard.set("off", forKey: "polishEngine")
        unloadPolishEngine()
        try? FileManager.default.removeItem(at: PolishModelCatalog.localURL)
    }

    /// Arm the debounce: unload the warm model after polishIdleUnload with no new
    /// dictation. Called when a dictation completes; cancelled at record-start.
    @MainActor
    private func schedulePolishIdleUnload() {
        polishIdleTimer?.invalidate()
        polishIdleTimer = Timer.scheduledTimer(withTimeInterval: Self.polishIdleUnload,
                                               repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.unloadPolishEngine() }
        }
    }

    @MainActor
    private func cancelPolishIdleUnload() {
        polishIdleTimer?.invalidate()
        polishIdleTimer = nil
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop it was scheduled from, so the
            // @Sendable block is already on the main actor.
            MainActor.assumeIsolated {
                guard let self else { return }
                let elapsed = self.recorder.elapsedSeconds
                self.appState.elapsedSeconds = elapsed

                // VAD auto-stop while recording.
                guard self.vadEnabled,
                      case .recording = self.appState.phase
                else { return }

                if self.appState.currentLevel > Self.voiceThreshold {
                    self.lastVoiceAt = Date()
                }
                if let lastVoice = self.lastVoiceAt,
                   elapsed >= Self.vadMinDuration,
                   Date().timeIntervalSince(lastVoice) >= self.vadSilenceSeconds {
                    self.stopAndTranscribe()
                }
            }
        }
    }

    private func playSound(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    /// Stop the frame pump and wait for buffered audio to reach the streaming
    /// transcriber before continuing, so `finish()` returns the complete text.
    /// Safe to call when no stream is wired.
    private func tearDownFramesPump() async {
        recorder.framesHandler = nil
        framesContinuation?.finish()
        framesContinuation = nil
        if let task = framesPumpTask {
            framesPumpTask = nil
            await task.value
        }
    }

    /// Let the last finalized phrase reach the focused app before restoring
    /// the pre-recording clipboard. Also closes an interrupted Inline session.
    private func finishInlineInsertion() async {
        guard let task = inlineInsertTask else { return }
        await task.value
        await MainActor.run {
            PasteService.endSequentialSession()
            inlineInsertTask = nil
        }
    }

    private func finishOverlayPreview() async {
        if let task = overlayPreviewTask { await task.value }
        overlayPreviewTask = nil
        await MainActor.run { appState.livePreview = "" }
    }


    /// Read the recorder's WAV back as float samples. Used to feed history
    /// when the user has audio storage enabled. The recorder writes at the
    /// input device's native rate; we preserve that and let HistoryStore
    /// encode at whatever rate it received.
    static func loadAudioSamples(from url: URL) -> (samples: [Float], sampleRate: Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        return (samples, format.sampleRate)
    }


    /// Reads the crash sentinel and immediately re-arms it for this session.
    /// Returns true if the prior session didn't exit cleanly.
    @MainActor
    private func checkAndMarkCrashSentinel() -> Bool {
        let didCrash = UserDefaults.standard.bool(forKey: "crashSentinel")
        UserDefaults.standard.set(true, forKey: "crashSentinel")
        return didCrash
    }

    @MainActor
    private func offerCrashBugReport() async {
        let alert = NSAlert()
        alert.messageText = "Murmur didn't exit cleanly last time."
        alert.informativeText = "This is usually a crash or force-quit. Filing a report helps us fix it. We'll open a diagnostics file in Finder you can drag into the issue."
        alert.addButton(withTitle: "Report Bug")
        alert.addButton(withTitle: "Dismiss")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        writeDiagnosticsFileAndReveal()
        guard let url = URL(string: "https://github.com/jackammon/murmur/issues/new?template=bug_report.yml") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Write local recording diagnostics for the user to review and share.
    /// Includes durations, counts, RTF, detected-language code, and event labels,
    /// never transcript text. Returns nil if the file cannot be written.
    /// The Stats pane also uses this method to reveal its report.
    @MainActor
    @discardableResult
    func writeDiagnosticsFileAndReveal() -> URL? {
        let report = DiagnosticsReport.render(
            appVersion: MurmurKit.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            chip: Self.chipString(),
            model: appState.modelLabel,
            lastRecording: lastRecordingDiag,
            events: Diagnostics.shared.recentEvents(),
            generatedAt: Date()
        )
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("diagnostics-\(Self.fileTimestamp()).txt")
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Diagnostics.shared.log(.app, .error, "diagnostics write failed: \(error)")
            return nil
        }
        Diagnostics.shared.log(.app, .info, "wrote diagnostics to \(url.lastPathComponent)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    /// CPU brand string (e.g. "Apple M4") for the diagnostics header.
    private static func chipString() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "unknown CPU" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    /// On launch, surface any recordings that didn't complete transcription.
    /// Show an alert so the user can recover or discard the recording.
    @MainActor
    private func offerRecoveryIfNeeded() async {
        let entries = await historyStore.recoverable()
        guard !entries.isEmpty else { return }

        let alert = NSAlert()
        if entries.count == 1 {
            let mins = max(1, Int(Date().timeIntervalSince(entries[0].recordedAt) / 60))
            alert.messageText = "We found a recording from \(mins) min ago that didn't finish."
            alert.informativeText = "Recover transcribes the audio and pastes the result. Discard deletes the recording."
            alert.addButton(withTitle: "Recover")
            alert.addButton(withTitle: "Discard")
        } else {
            alert.messageText = "\(entries.count) recordings to recover."
            alert.informativeText = "Recover all transcribes each one and pastes the results. Discard all deletes them."
            alert.addButton(withTitle: "Recover all")
            alert.addButton(withTitle: "Discard all")
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for entry in entries { await recoverEntry(entry) }
        case .alertSecondButtonReturn:
            for entry in entries { try? await historyStore.delete(entry.id) }
        default: break
        }
    }

    @MainActor
    private func recoverEntry(_ entry: HistoryEntry) async {
        guard let audioURL = entry.audioURL else { return }
        // Engine may not be warm yet at this stage; warm if needed before
        // attempting recovery so the user-facing flow doesn't error out.
        if transcriber == nil { startWarm(); await warmTask?.value }
        guard let engine = transcriber else { return }
        do {
            let result = try await engine.transcribe(
                audioFile: audioURL,
                language: defaultLanguage,
                customWords: customWords
            )
            let polished = (await polishedTranscript(from: result.text)).text
            let autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
            if autoPasteEnabled {
                _ = textInserter.insert(polished)
            } else {
                PasteService.copyToClipboard(polished)
            }
            schedulePolishIdleUnload()
            try? await historyStore.markTranscribed(entry.id, transcript: polished)
            await usageStats.record(transcript: polished, audioSeconds: result.audioSeconds)
        } catch {
            // Best-effort — leave the entry recoverable for next launch.
        }
    }


    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "crashSentinel")
    }
}
