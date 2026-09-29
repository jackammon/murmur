import Foundation

/// A chunk-local energy gate. A session-level peak cannot tell whether a
/// later, quiet chunk contains speech after an earlier voiced phrase.
enum ChunkSpeechGate {
    static func hasSpeech(_ samples: [Float], threshold: Float,
                          sampleRate: Int = 16000) -> Bool {
        guard !samples.isEmpty, threshold > 0, sampleRate > 0 else { return false }
        let windowLength = max(1, sampleRate / 10) // 100 ms
        var start = 0
        while start < samples.count {
            let end = min(start + windowLength, samples.count)
            var sumSquares: Float = 0
            for sample in samples[start..<end] { sumSquares += sample * sample }
            let rms = sqrt(sumSquares / Float(end - start))
            if rms >= threshold { return true }
            start = end
        }
        return false
    }
}
