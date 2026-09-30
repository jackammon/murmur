import Foundation

/// One transcription run's measured output. Engines fill what they know;
/// fields they don't measure are nil.
public struct EngineTranscription: Sendable {
    public var text: String
    public var detectedLanguage: String?
    public var audioSeconds: TimeInterval     // length of input
    public var wallSeconds: TimeInterval      // wall-clock spent inside transcribe()
    public var timeToFirstToken: TimeInterval?

    public init(
        text: String,
        detectedLanguage: String? = nil,
        audioSeconds: TimeInterval,
        wallSeconds: TimeInterval,
        timeToFirstToken: TimeInterval? = nil
    ) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.audioSeconds = audioSeconds
        self.wallSeconds = wallSeconds
        self.timeToFirstToken = timeToFirstToken
    }
}

public enum EngineError: Error, CustomStringConvertible {
    case modelNotSupported(String)
    case loadFailed(String)
    case runtimeFailed(String)

    public var description: String {
        switch self {
        case .modelNotSupported(let m): return "Model not supported: \(m)"
        case .loadFailed(let s):        return "Engine load failed: \(s)"
        case .runtimeFailed(let s):     return "Engine runtime failed: \(s)"
        }
    }
}

public protocol TranscriptionEngine: AnyObject {
    static var engineName: String { get }
    /// Suggested models — engines may accept other identifiers; this is a hint for `--help`.
    static var suggestedModels: [String] { get }

    var modelID: String { get }

    func transcribe(audioFile url: URL, language: String?) async throws -> EngineTranscription
}
