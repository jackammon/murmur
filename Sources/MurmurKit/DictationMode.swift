import Foundation

public enum DictationMode: String, CaseIterable, Sendable {
    case batch
    case overlay
    case inline

    public static func fromStored(_ value: String?) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? .batch
    }

    public var title: String {
        switch self {
        case .batch: "Batch"
        case .overlay: "Overlay"
        case .inline: "Inline"
        }
    }

    /// Inline commits chunks as they finish; the final assembled transcript
    /// is only for history and status, never a second cursor insertion.
    public var pastesFinalTranscript: Bool { self != .inline }

    /// Batch keeps its duration-based offline/streaming choice. The other
    /// modes need a running streamer for phrase delivery or live preview.
    public var streamsFromStart: Bool { self != .batch }

    /// Snapshot the output choice at recording start. Inline must honor the
    /// same clipboard-only preference as the other modes before any phrase
    /// can be inserted.
    public func outputPlan(autoPasteEnabled: Bool) -> DictationOutputPlan {
        guard autoPasteEnabled else { return .copyFinalTranscript }
        return self == .inline ? .insertFinalizedChunks : .pasteFinalTranscript
    }
}

public enum DictationOutputPlan: Equatable, Sendable {
    case insertFinalizedChunks
    case pasteFinalTranscript
    case copyFinalTranscript
}
