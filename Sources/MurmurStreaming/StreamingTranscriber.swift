import Foundation
import MurmurPlatform
import WhisperKit

/// SPEC-012: streaming transcription that chunks audio at silence boundaries
/// while recording is still in flight, so post-stop wait is bounded by
/// `maxChunkSeconds * RTF` instead of growing with utterance length.
///
/// Owned by the bench harness today; re-homes into `MurmurKit/Streaming/`
/// when the AppDelegate wiring lands. Public surface is the one in
/// `docs/SPECS/SPEC-012-streaming-transcription.md`.
public actor StreamingTranscriber {
    public struct Config: Sendable {
        /// Below this many seconds the caller should bypass streaming and
        /// transcribe offline; the actor still works for shorter clips, but
        /// for the M4/16GB / WhisperKit-medium baseline the offline path is
        /// faster end-to-end on short audio.
        public var streamingThreshold: TimeInterval
        /// Cuts happen at the next silence past this mark, never before.
        public var targetChunkSeconds: TimeInterval
        /// If no silence is found by this point, force-cut anyway.
        public var maxChunkSeconds: TimeInterval
        /// Energy threshold passed through to `EnergyVAD`.
        public var silenceEnergyThreshold: Float
        /// Minimum 100 ms window RMS for a chunk to reach the decoder.
        /// Matches the recorder's whole-session silence gate by default.
        public var minimumSpeechRMS: Float
        /// Cap on chunks transcribing at once. Default 1: bumping it gives
        /// headroom against RTF spikes at the cost of double peak RAM.
        public var maxInFlightChunks: Int
        /// Shortest chunk the auto path trusts to re-detect language on
        /// (SPEC-035). Interior chunks are ≥ `targetChunkSeconds` and always
        /// re-detect; a trailing chunk shorter than this inherits the running
        /// language instead of risking a weak-detection flip. Default 10 s —
        /// comfortably above Whisper's reliable language-ID floor while still
        /// well under a full chunk, so only genuinely short tails inherit.
        public var minDetectSeconds: TimeInterval
        /// Opt-in rough Overlay preview cadence and rolling decode window.
        public var previewIntervalSeconds: TimeInterval
        public var previewWindowSeconds: TimeInterval

        public init(
            streamingThreshold: TimeInterval = 30,
            targetChunkSeconds: TimeInterval = 20,
            maxChunkSeconds: TimeInterval = 28,
            silenceEnergyThreshold: Float = 0.02,
            minimumSpeechRMS: Float = 0.005,
            maxInFlightChunks: Int = 1,
            minDetectSeconds: TimeInterval = 10,
            previewIntervalSeconds: TimeInterval = 0.8,
            previewWindowSeconds: TimeInterval = 8
        ) {
            self.streamingThreshold = streamingThreshold
            self.targetChunkSeconds = targetChunkSeconds
            self.maxChunkSeconds = maxChunkSeconds
            self.silenceEnergyThreshold = silenceEnergyThreshold
            self.minimumSpeechRMS = minimumSpeechRMS
            self.maxInFlightChunks = maxInFlightChunks
            self.minDetectSeconds = minDetectSeconds
            self.previewIntervalSeconds = previewIntervalSeconds
            self.previewWindowSeconds = previewWindowSeconds
        }
    }

    public struct Result: Sendable {
        public let text: String
        public let detectedLanguage: String?
        public let audioSeconds: Double
        public let wallSeconds: Double
        public let chunkCount: Int
        public let chunkFailures: Int
    }

    /// A completed audio chunk, including the final tail submitted by
    /// `finish()`. Raw text is deliberately unpolished; Batch still assembles
    /// and polishes the complete utterance through its existing path.
    public struct FinalizedChunk: Sendable, Equatable {
        public let startSample: Int
        public let sampleCount: Int
        public let text: String
        public let detectedLanguage: String?
        public let succeeded: Bool
        public let isTail: Bool
        public let hasSpeechEnergy: Bool

        public var audioSeconds: Double { Double(sampleCount) / 16000 }

        public init(
            startSample: Int, sampleCount: Int, text: String,
            detectedLanguage: String?, succeeded: Bool, isTail: Bool,
            hasSpeechEnergy: Bool = true
        ) {
            self.startSample = startSample
            self.sampleCount = sampleCount
            self.text = text
            self.detectedLanguage = detectedLanguage
            self.succeeded = succeeded
            self.isTail = isTail
            self.hasSpeechEnergy = hasSpeechEnergy
        }
    }

    private let pipe: WhisperKit
    private let config: Config
    private let vad: EnergyVAD
    private let sampleRate: Int = 16000

    private var buffer: [Float] = []
    private var bufferStartSample: Int = 0
    private var beginTime: Date?
    private var language: String?
    /// On the auto path (`language == nil`), the language detected on the most
    /// recent *full* chunk. Full chunks re-detect (so a mid-recording language
    /// switch is honoured); a short trailing chunk inherits this instead of
    /// risking a weak-detection flip (SPEC-035, `decideStreamingChunk`).
    private var runningLanguage: String?
    private var promptTokens: [Int]?
    private var ended: Bool = false
    private var cancelled: Bool = false
    private var sessionGeneration: UInt64 = 0

    private struct ChunkOutcome: Sendable {
        let text: String
        let detectedLanguage: String?
        let succeeded: Bool
    }

    /// Outcomes keyed by their starting sample (global, monotonic) so the
    /// caller can re-order on `finish()`.
    private var chunkOutcomes: [Int: ChunkOutcome] = [:]
    private var queue: [(start: Int, samples: [Float], isTail: Bool)] = []
    private var drainTask: Task<Void, Never>?
    private var finalizedDelivery = OrderedFinalizedChunkDelivery()
    private var previewDelivery = RoughPreviewDelivery()
    private var previewLoopTask: Task<Void, Never>?
    private var previewDecodeTask: Task<String?, Never>?
    private var latestPreviewTail = ""
    private var lastPreviewedSample = 0

    public init(pipe: WhisperKit, config: Config = .init()) {
        self.pipe = pipe
        self.config = config
        self.vad = EnergyVAD(
            sampleRate: 16000,
            frameLength: 0.1,
            frameOverlap: 0,
            energyThreshold: config.silenceEnergyThreshold
        )
    }

    public func begin(language: String?, customWords: String?) async {
        sessionGeneration &+= 1
        let beginningGeneration = sessionGeneration
        finalizedDelivery.cancel()
        previewDelivery.cancel()
        previewLoopTask?.cancel()
        previewLoopTask = nil
        previewDecodeTask?.cancel()
        // If a prior session's drain is still in flight, fully tear it down
        // before resetting state. Otherwise the old drain can re-check
        // `cancelled` after we reset it to false and write its outcome into
        // the new session's `chunkOutcomes`, mixing two recordings.
        if let prior = drainTask {
            cancelled = true
            prior.cancel()
            await prior.value
        }
        if let priorPreview = previewDecodeTask { _ = await priorPreview.value }
        guard beginningGeneration == sessionGeneration else { return }
        buffer.removeAll(keepingCapacity: true)
        bufferStartSample = 0
        chunkOutcomes.removeAll()
        queue.removeAll()
        finalizedDelivery.begin()
        previewDelivery.begin(generation: sessionGeneration)
        previewDecodeTask = nil
        latestPreviewTail = ""
        lastPreviewedSample = 0
        drainTask = nil
        ended = false
        cancelled = false
        beginTime = Date()
        self.language = language
        self.runningLanguage = nil
        self.promptTokens = encodePrompt(customWords: customWords)
    }

    public func appendFrames(_ samples: [Float], sampleRate inputRate: Double) {
        guard !cancelled, !ended else { return }
        let resampled = resampleIfNeeded(samples, from: inputRate)
        buffer.append(contentsOf: resampled)
        emitChunksIfReady()
    }

    /// One consumer per recording. Call after `begin()`; the stream buffers
    /// completed chunks until that consumer reads them. `finish()` and
    /// `cancel()` terminate it. The old stream ends when a new session begins.
    public func finalizedChunks() -> AsyncStream<FinalizedChunk> {
        finalizedDelivery.stream ?? AsyncStream { $0.finish() }
    }

    /// SPEC-054 — opt-in rough preview. One consumer per session; calling
    /// this starts the periodic decode loop. No UI or paste work occurs here.
    public func partialPreview() -> AsyncStream<String> {
        if previewLoopTask == nil, !cancelled, !ended {
            let generation = sessionGeneration
            previewLoopTask = Task { [weak self] in
                await self?.runPreviewLoop(generation: generation)
            }
        }
        return previewDelivery.stream ?? AsyncStream { $0.finish() }
    }

    public func finish() async throws -> Result {
        let finishingGeneration = sessionGeneration
        ended = true
        previewLoopTask?.cancel()
        previewLoopTask = nil
        previewDecodeTask?.cancel()
        // Submit whatever's left as the tail.
        if !buffer.isEmpty {
            let tail = buffer
            buffer.removeAll(keepingCapacity: true)
            let start = bufferStartSample
            bufferStartSample += tail.count
            queue.append((start: start, samples: tail, isTail: true))
            startDrainIfNeeded()
        }
        // Wait for the queue to fully drain.
        await drainTask?.value
        if let previewDecodeTask { _ = await previewDecodeTask.value }
        guard finishingGeneration == sessionGeneration, !cancelled else {
            throw CancellationError()
        }
        finalizedDelivery.finish()
        previewDelivery.finish()
        previewDecodeTask = nil

        let ordered = chunkOutcomes.keys.sorted().compactMap { chunkOutcomes[$0] }
        let texts = ordered.map(\.text).filter { !$0.isEmpty }
        let text = stitchChunks(texts).trimmingCharacters(in: .whitespacesAndNewlines)
        let lang = ordered.compactMap(\.detectedLanguage).first
        let failures = ordered.filter { !$0.succeeded }.count

        let audioSecs = Double(bufferStartSample) / Double(sampleRate)
        let wall = beginTime.map { Date().timeIntervalSince($0) } ?? 0

        return Result(
            text: text,
            detectedLanguage: lang,
            audioSeconds: audioSecs,
            wallSeconds: wall,
            chunkCount: ordered.count,
            chunkFailures: failures
        )
    }

    public func cancel() {
        sessionGeneration &+= 1
        cancelled = true
        ended = true
        drainTask?.cancel()
        previewLoopTask?.cancel()
        previewLoopTask = nil
        previewDecodeTask?.cancel()
        drainTask = nil
        queue.removeAll()
        buffer.removeAll(keepingCapacity: false)
        chunkOutcomes.removeAll()
        finalizedDelivery.cancel()
        previewDelivery.cancel()
        latestPreviewTail = ""
        beginTime = nil
        runningLanguage = nil
    }

    // MARK: - cut-point logic

    private func emitChunksIfReady() {
        let target = Int(config.targetChunkSeconds) * sampleRate
        let max_   = Int(config.maxChunkSeconds)    * sampleRate
        // While we have at least targetSeconds buffered, decide whether to
        // cut. If we have ≥ max, we cut at the next silence inside [target,
        // max] — or force-cut at max if no silence was found.
        while buffer.count >= target {
            let windowEnd = min(buffer.count, max_)
            let cutSample: Int
            if let cut = findCutPoint(start: target, end: windowEnd) {
                cutSample = cut
            } else if buffer.count >= max_ {
                cutSample = max_
            } else {
                break  // wait for more frames; silence may yet appear
            }

            let chunk = Array(buffer.prefix(cutSample))
            buffer.removeFirst(cutSample)
            let start = bufferStartSample
            bufferStartSample += cutSample
            queue.append((start: start, samples: chunk, isTail: false))
            startDrainIfNeeded()
        }
    }

    /// Mirrors `VADAudioChunker.splitOnMiddleOfLongestSilence`: search the
    /// second half of `[start, end)` for the longest silence, return the
    /// audio-sample index of its midpoint. Nil when no silence found.
    private func findCutPoint(start: Int, end: Int) -> Int? {
        guard end > start, end <= buffer.count else { return nil }
        let mid = start + (end - start) / 2
        guard mid < end else { return nil }
        let slice = Array(buffer[mid..<end])
        let voice = vad.voiceActivity(in: slice)
        guard let silence = vad.findLongestSilence(in: voice) else { return nil }
        let silenceMidVAD = silence.startIndex + (silence.endIndex - silence.startIndex) / 2
        return mid + vad.voiceActivityIndexToAudioSampleIndex(silenceMidVAD)
    }

    // MARK: - drain queue (bounded by maxInFlightChunks)

    private func startDrainIfNeeded() {
        guard drainTask == nil, !cancelled else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            if cancelled { break }
            // A finalized chunk owns the shared WhisperKit pipe. Wait for
            // any in-progress rough pass before transcribing sealed audio.
            if let previewDecodeTask {
                previewDecodeTask.cancel()
                _ = await previewDecodeTask.value
                self.previewDecodeTask = nil
            }
            if cancelled { break }
            // For maxInFlightChunks=1 we just transcribe one at a time.
            // (Bumping to N would batch N at a time; deferred until the
            // RAM/RTF trade-off is benched per SPEC-012.)
            let next = queue.removeFirst()
            let hasSpeechEnergy = ChunkSpeechGate.hasSpeech(
                next.samples, threshold: config.minimumSpeechRMS)
            let outcome = hasSpeechEnergy
                ? await transcribeOne(samples: next.samples)
                : ChunkOutcome(text: "", detectedLanguage: nil, succeeded: true)
            // cancel() may have raced while we awaited transcribeOne; if so
            // discard the result so the post-cancel state stays clean.
            if cancelled { break }
            chunkOutcomes[next.start] = outcome
            finalizedDelivery.record(FinalizedChunk(
                startSample: next.start,
                sampleCount: next.samples.count,
                text: outcome.text,
                detectedLanguage: outcome.detectedLanguage,
                succeeded: outcome.succeeded,
                isTail: next.isTail,
                hasSpeechEnergy: hasSpeechEnergy
            ))
            latestPreviewTail = ""
            if previewLoopTask != nil { publishRoughPreview() }
        }
        drainTask = nil
    }

    // MARK: - opt-in rough preview

    private func runPreviewLoop(generation: UInt64) async {
        let interval = max(0.1, config.previewIntervalSeconds)
        while !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
            catch { break }
            await previewTick(generation: generation)
        }
    }

    private func previewTick(generation: UInt64) async {
        guard generation == sessionGeneration, !cancelled, !ended,
              drainTask == nil, previewDecodeTask == nil else { return }
        let sampleEnd = bufferStartSample + buffer.count
        guard sampleEnd != lastPreviewedSample else { return }
        let policy = RoughPreviewPolicy(
            sampleRate: sampleRate,
            windowSeconds: config.previewWindowSeconds,
            // The cut-point VAD's default 0.02 RMS is too high for normal
            // microphone levels on this Mac: a clearly spoken test peaked at
            // 0.012. Use the recorder-aligned speech gate for preview input.
            energyThreshold: config.minimumSpeechRMS
        )
        guard let input = policy.input(from: buffer, pinnedLanguage: language) else { return }
        lastPreviewedSample = sampleEnd
        let prompt = promptTokens
        let task = Task<String?, Never> { [pipe] in
            var options = DecodingOptions()
            options.task = .transcribe
            options.verbose = false
            options.withoutTimestamps = true
            options.language = input.language
            options.detectLanguage = false
            if let prompt, !prompt.isEmpty { options.promptTokens = prompt }
            do {
                let results = try await pipe.transcribe(audioArray: input.samples, decodeOptions: options)
                return results.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            } catch { return nil }
        }
        previewDecodeTask = task
        let text = await task.value
        guard generation == sessionGeneration, !cancelled, !ended else { return }
        previewDecodeTask = nil
        guard drainTask == nil, let text else { return }
        latestPreviewTail = text
        publishRoughPreview()
    }

    private func publishRoughPreview() {
        let stable = chunkOutcomes.keys.sorted().compactMap { chunkOutcomes[$0]?.text }
        let parts = stable + [latestPreviewTail]
        let text = stitchChunks(parts.filter { !$0.isEmpty })
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        previewDelivery.record(text, generation: sessionGeneration)
    }

    private func transcribeOne(samples: [Float]) async -> ChunkOutcome {
        var options = DecodingOptions()
        options.task = .transcribe
        options.verbose = false
        options.withoutTimestamps = true
        if let p = promptTokens, !p.isEmpty {
            options.promptTokens = p
        }

        // Per-chunk language decision on the auto path (SPEC-035). WhisperKit
        // only detects when `language == nil && detectLanguage` (the latter
        // defaults false), so without this every chunk silently prefills English
        // and translates non-English audio (SPEC-021). Rather than lock the whole
        // session to the first chunk — which forces a mid-recording language
        // switch back to the original language — each *full* chunk re-detects,
        // and only a short trailing chunk inherits the running language (it can
        // be too short for reliable detection, and WhisperKit returns the "en"
        // fallback when unsure). A pinned language skips detection entirely. See
        // `decideStreamingChunk` for the rationale and SPEC-035 §Streaming for
        // the before/after bench.
        let chunkSeconds = Double(samples.count) / Double(sampleRate)
        let decision = LanguageDecodePolicy.decideStreamingChunk(
            pinned: language,
            running: runningLanguage,
            chunkSeconds: chunkSeconds,
            minDetectSeconds: config.minDetectSeconds
        )
        options.language = decision.language
        options.detectLanguage = decision.detectLanguage

        let t0 = Date()
        do {
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let detected = results.first?.language
            // Update the running language only from a chunk that actually
            // re-detected (a full chunk) and produced text — a short inherited
            // chunk must not overwrite it, and an empty (silence) chunk yields
            // the "en" fallback and must not pin English.
            if language == nil, decision.detectLanguage, !text.isEmpty, let detected {
                runningLanguage = detected
            }
            // SPEC-036 — per-chunk timing/RTF + language decision. Chunks are
            // ~20 s apart so this is cheap; it's what lets us confirm "slow"
            // (RTF, and detect-every-chunk doubling cost) and "inaccurate"
            // (a language flip on an interior chunk) from a user's session.
            let wall = Date().timeIntervalSince(t0)
            let rtf = chunkSeconds > 0 ? wall / chunkSeconds : 0
            Diagnostics.shared.log(.streaming, .info, String(
                format: "chunk %.1fs detect=%@ lang=%@ → wall %.2fs rtf %.2f detected=%@ %dchars",
                chunkSeconds,
                decision.detectLanguage ? "y" : "n",
                decision.language ?? "auto",
                wall, rtf,
                detected ?? "-",
                text.count
            ))
            return ChunkOutcome(text: text, detectedLanguage: detected, succeeded: true)
        } catch {
            let wall = Date().timeIntervalSince(t0)
            Diagnostics.shared.log(.streaming, .error, String(
                format: "chunk %.1fs FAILED after %.2fs: %@", chunkSeconds, wall, "\(error)"
            ))
            return ChunkOutcome(text: "", detectedLanguage: nil, succeeded: false)
        }
    }

    // MARK: - chunk stitching

    /// Whisper occasionally re-emits the boundary word when a chunk starts
    /// mid-utterance. Per SPEC-012 §Stop semantics step 4 we drop a single
    /// trailing/leading duplicate at each chunk seam. Comparison normalises
    /// case and strips trailing punctuation; keeps the longer-cased form.
    private func stitchChunks(_ chunks: [String]) -> String {
        guard let first = chunks.first else { return "" }
        var out = first
        for next in chunks.dropFirst() {
            let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nextTrimmed.isEmpty else { continue }

            let lastWord = lastWord(of: out)
            let nextWords = nextTrimmed.split(whereSeparator: { $0.isWhitespace })
            let firstWord = nextWords.first.map(String.init) ?? ""

            if !lastWord.isEmpty,
               wordKey(lastWord) == wordKey(firstWord) {
                let stripped = nextWords.dropFirst().joined(separator: " ")
                if !stripped.isEmpty { out += " " + stripped }
            } else {
                out += " " + nextTrimmed
            }
        }
        return out
    }

    private func lastWord(of s: String) -> String {
        let parts = s.split(whereSeparator: { $0.isWhitespace })
        return parts.last.map(String.init) ?? ""
    }

    private func wordKey(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    // MARK: - prompt + resampling

    private func encodePrompt(customWords: String?) -> [Int]? {
        guard let words = customWords?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else {
            return nil
        }
        let joined = words
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !joined.isEmpty, let tok = pipe.tokenizer else { return nil }
        return tok.encode(text: " " + joined)
    }

    private func resampleIfNeeded(_ samples: [Float], from inputRate: Double) -> [Float] {
        let inRate = Int(inputRate.rounded())
        if inRate == sampleRate || inRate == 0 { return samples }
        // Simple linear-interpolation resampler. Good enough for VAD/Whisper
        // (which downsample further internally). For the bench we feed 16 kHz
        // direct, so this path is exercised only when wired to AudioRecorder
        // in AppDelegate at 44.1/48 kHz.
        let inCount = samples.count
        guard inCount > 1 else { return samples }
        let ratio = Double(sampleRate) / Double(inRate)
        let outCount = Int(Double(inCount) * ratio)
        var out = [Float](repeating: 0, count: outCount)
        let step = 1.0 / ratio
        for i in 0..<outCount {
            let pos = Double(i) * step
            let i0 = Int(pos)
            let i1 = min(i0 + 1, inCount - 1)
            let t = Float(pos - Double(i0))
            out[i] = samples[i0] * (1 - t) + samples[i1] * t
        }
        return out
    }
}

/// Session-scoped reorder buffer. The current drain is serial, but ordering
/// here remains correct if `maxInFlightChunks` later permits parallel decode.
/// Internal so synthetic outcomes can test delivery without Whisper weights.
struct OrderedFinalizedChunkDelivery {
    private(set) var stream: AsyncStream<StreamingTranscriber.FinalizedChunk>?
    private var continuation: AsyncStream<StreamingTranscriber.FinalizedChunk>.Continuation?
    private var pending: [Int: StreamingTranscriber.FinalizedChunk] = [:]
    private var nextSample = 0
    private var completed = false

    mutating func begin() {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<StreamingTranscriber.FinalizedChunk>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.stream = stream
        self.continuation = continuation
        pending.removeAll()
        nextSample = 0
        completed = false
    }

    mutating func record(_ chunk: StreamingTranscriber.FinalizedChunk) {
        guard !completed, chunk.sampleCount > 0,
              chunk.startSample >= nextSample,
              pending[chunk.startSample] == nil else { return }
        pending[chunk.startSample] = chunk
        while let next = pending.removeValue(forKey: nextSample) {
            continuation?.yield(next)
            nextSample += next.sampleCount
        }
    }

    mutating func finish() {
        guard !completed else { return }
        completed = true
        pending.removeAll()
        continuation?.finish()
        continuation = nil
    }

    mutating func cancel() {
        finish()
    }
}

/// Selects a bounded, voiced window before any expensive preview decode.
/// Kept separate from the actor so the silence and language policy can be
/// tested without a Whisper model.
struct RoughPreviewPolicy {
    struct Input {
        let samples: [Float]
        let language: String
    }

    let sampleRate: Int
    let windowSeconds: TimeInterval
    let energyThreshold: Float

    func input(from buffer: [Float], pinnedLanguage: String?) -> Input? {
        let minSamples = Int(0.8 * Double(sampleRate))
        guard buffer.count >= minSamples else { return nil }
        let windowSamples = max(minSamples, Int(windowSeconds * Double(sampleRate)))
        let window = Array(buffer.suffix(windowSamples))
        let vad = EnergyVAD(sampleRate: sampleRate, frameLength: 0.1,
                            frameOverlap: 0, energyThreshold: energyThreshold)
        guard vad.voiceActivity(in: window).contains(true) else { return nil }
        let pinned = pinnedLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLanguage = pinned.flatMap { $0.isEmpty ? nil : $0 } ?? "en"
        return Input(samples: window, language: resolvedLanguage)
    }
}

/// One buffered preview stream per recording. Duplicate text is suppressed;
/// cancel/new begin complete the old stream before any new delivery.
struct RoughPreviewDelivery {
    private(set) var stream: AsyncStream<String>?
    private var continuation: AsyncStream<String>.Continuation?
    private var lastText = ""
    private var completed = false
    private var generation: UInt64 = 0

    mutating func begin(generation: UInt64) {
        continuation?.finish()
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(2))
        self.stream = stream
        self.continuation = continuation
        lastText = ""
        completed = false
        self.generation = generation
    }

    mutating func record(_ text: String, generation: UInt64) {
        guard !completed, generation == self.generation,
              !text.isEmpty, text != lastText else { return }
        lastText = text
        continuation?.yield(text)
    }

    mutating func finish() {
        guard !completed else { return }
        completed = true
        continuation?.finish()
        continuation = nil
    }

    mutating func cancel() { finish() }
}
