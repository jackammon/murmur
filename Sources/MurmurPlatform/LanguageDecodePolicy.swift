import Foundation

/// Pure decision for choosing WhisperKit language handling across offline and
/// streaming transcription paths.
public enum LanguageDecodePolicy {
    public struct Decision: Equatable, Sendable {
        /// Value for `DecodingOptions.language` (nil ⇒ let the decoder detect).
        public let language: String?
        /// Value for `DecodingOptions.detectLanguage`.
        public let detectLanguage: Bool

        public init(language: String?, detectLanguage: Bool) {
            self.language = language
            self.detectLanguage = detectLanguage
        }
    }

    /// - Parameters:
    ///   - pinned: a user-selected language code, or nil for auto.
    ///   - locked: a language already resolved earlier in the same streaming
    ///     session, or nil. Ignored when `pinned` is set. Pass nil on the
    ///     stateless offline path.
    public static func decide(pinned: String?, locked: String? = nil) -> Decision {
        if let pinned, !pinned.isEmpty {
            return Decision(language: pinned, detectLanguage: false)
        }
        if let locked, !locked.isEmpty {
            return Decision(language: locked, detectLanguage: false)
        }
        return Decision(language: nil, detectLanguage: true)
    }

    ///
    /// The old rule locked the language to the first chunk for the whole
    /// session, so an utterance that switched language mid-recording (English
    /// then Chinese) was forced to the first language and the rest was
    /// mistranscribed. The opposite extreme — re-detect every chunk — re-exposes
    /// the weak-detection failure that lock was added to fix: WhisperKit returns
    /// the `"en"` fallback (not nil) when detection is unsure, so a short,
    /// low-content chunk can silently flip a monolingual recording's tail to the
    /// wrong language.
    ///
    /// The middle ground keys off chunk duration. Interior chunks are always
    /// ≥ `targetChunkSeconds` (the cutter never emits shorter), long enough for
    /// reliable language ID, so they **re-detect** — that's what lets the
    /// language switch at a chunk boundary. Only the trailing partial chunk can
    /// be short; below `minDetectSeconds` it **inherits** the running language
    /// instead of risking a misdetect. The first chunk has nothing to inherit,
    /// so a (rare) short first chunk still detects.
    ///
    /// - Parameters:
    ///   - pinned: user-selected language, or nil for auto.
    ///   - running: the language detected on the most recent full chunk, or nil.
    ///   - chunkSeconds: duration of the chunk about to be decoded.
    ///   - minDetectSeconds: shortest chunk we trust to re-detect.
    public static func decideStreamingChunk(
        pinned: String?,
        running: String?,
        chunkSeconds: Double,
        minDetectSeconds: Double
    ) -> Decision {
        if let pinned, !pinned.isEmpty {
            return Decision(language: pinned, detectLanguage: false)
        }
        // Full chunk → re-detect, so the language can change mid-recording.
        if chunkSeconds >= minDetectSeconds {
            return Decision(language: nil, detectLanguage: true)
        }
        // Short tail chunk → inherit rather than risk a weak-detection flip.
        if let running, !running.isEmpty {
            return Decision(language: running, detectLanguage: false)
        }
        // Nothing to inherit (short first chunk): detect anyway.
        return Decision(language: nil, detectLanguage: true)
    }
}
