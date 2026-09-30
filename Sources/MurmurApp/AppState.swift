import Foundation
import Combine
import MurmurKit
import MurmurPlatform

public final class AppState: ObservableObject {
    public enum Phase: Equatable {
        case warming(modelLabel: String)
        case idle
        case starting
        case recording
        case transcribing
        case polishing
        case ready
        case error(String)
    }

    @Published public var phase: Phase = .warming(modelLabel: "medium")
    @Published public var activeDictationMode: DictationMode = .batch
    @Published public var livePreview: String = ""
    @Published public var elapsedSeconds: Double = 0
    @Published public var currentLevel: Float = 0  // 0…1 RMS, for the level meter
    /// Sliding window of recent RMS samples (newest on the right). Drives the
    /// bigger waveform-style level meter in the recording overlay.
    @Published public var levelHistory: [Float] = Array(repeating: 0, count: AppState.barCount)
    @Published public var transcriptionProgress: Double = 0  // 0…1, observed from WhisperKit.progress

    public static let barCount = 11

    /// True while a recording is in flight, in any of its stages — the window
    /// during which the engine must not be swapped or its files removed.
    public var isDictating: Bool {
        switch phase {
        case .starting, .recording, .transcribing, .polishing: return true
        default: return false
        }
    }

    public func pushLevel(_ level: Float) {
        currentLevel = level
        var h = levelHistory
        h.removeFirst()
        h.append(level)
        levelHistory = h
    }

    public func resetLevels() {
        currentLevel = 0
        levelHistory = Array(repeating: 0, count: Self.barCount)
    }

    /// Store a finished recording summary, newest-first, capped at
    /// `recentRecordingsCap`. Call on the main actor to update published state.
    public func pushRecentRecording(_ summary: DiagnosticsReport.LastRecording) {
        recentRecordings.insert(summary, at: 0)
        if recentRecordings.count > Self.recentRecordingsCap {
            recentRecordings.removeLast(recentRecordings.count - Self.recentRecordingsCap)
        }
    }

    public var incompleteCaptureCount: Int {
        recentRecordings.filter { $0.health.isIncomplete }.count
    }
    @Published public var lastTranscript: String?
    @Published public var lastAudioSeconds: Double?
    @Published public var lastWallSeconds: Double?
    @Published public var lastRecordingURL: URL?
    @Published public var lastPasted: Bool = false
    /// Transient notice shown in the ready overlay subline,
    /// e.g. "Recording interrupted by an audio device change". Takes priority
    /// over the transcript preview when set; cleared at the next recording.
    @Published public var lastNotice: String?
    /// Recent recording-health summaries shown in Settings → Stats. Local-only;
    /// session-scoped, capped at `recentRecordingsCap`. Mutate via
    /// `pushRecentRecording(_:)` so the cap/order stay in one place.
    @Published public var recentRecordings: [DiagnosticsReport.LastRecording] = []
    public static let recentRecordingsCap = 10
    @Published public var accessibilityTrusted: Bool = false
    /// Microphone access was denied or is restricted. Refreshed when the
    /// popover opens; drives its "Microphone access is off" notice.
    @Published public var microphoneDenied: Bool = false
    /// Set when the most-recent recording came back silent (mic captured no
    /// usable audio — wrong/muted device). Drives the "Switch microphone"
    /// banner in the popover; cleared at the start of the next transcription.
    @Published public var lastCaptureSilent: Bool = false
    /// Name of the input device that produced the silent capture, for the
    /// banner/notification copy ("No sound from <device>").
    @Published public var lastSilentDeviceName: String?
    @Published public var modelLabel: String = "medium"
    /// Lifecycle of an update check — drives both the menu-bar update
    /// badge and the Settings → About status line. Single source of
    /// truth so a manual "Check for updates" click can flip from
    /// `.checking` to a terminal state and back to `.unknown` after a
    /// while if needed.
    @Published public var updateStatus: UpdateCheckStatus = .unknown
    @Published public var installMethod: InstallMethod = .manual
    /// Shared download progress used by the menu-bar banner.
    @Published public var polishDownload: PolishDownloadStatus = .inactive
    /// Drives the menu-bar download banner for the Whisper speech model.
    /// Carries the variant so the banner can name the model being downloaded.
    @Published public var speechDownload: SpeechDownloadStatus = .inactive

    /// Convenience for the popover banner — only present when the
    /// status terminal-states into `.available`.
    public var availableUpdate: UpdateChecker.ReleaseInfo? {
        if case .available(let release) = updateStatus { return release }
        return nil
    }

    public init() {}
}

public enum PolishDownloadStatus: Equatable {
    case inactive
    case downloading(fraction: Double)
}

public enum SpeechDownloadStatus: Equatable {
    case inactive
    /// `model` is the Whisper variant id (e.g. "large-v3").
    case downloading(model: String, fraction: Double)
}

public enum UpdateCheckStatus: Equatable {
    /// No check has run yet this launch.
    case unknown
    /// A check is in flight.
    case checking
    /// Latest reachable release is the running build.
    case upToDate(version: String, at: Date)
    /// Newer release found.
    case available(UpdateChecker.ReleaseInfo)
    /// Silent brew upgrade script is running; this instance is about to quit.
    case upgrading
    /// Last check failed (network, parse, etc).
    case failed(String)

    public var hasAvailableUpdate: Bool {
        if case .available = self { return true }
        return false
    }
}
