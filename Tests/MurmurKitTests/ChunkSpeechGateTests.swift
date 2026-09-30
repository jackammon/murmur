import XCTest
@testable import MurmurStreaming

final class ChunkSpeechGateTests: XCTestCase {
    func testSilentChunkAfterVoicedChunkIsStillSilent() {
        let voiced = Array(repeating: Float(0.02), count: 1600)
        let silent = Array(repeating: Float(0), count: 1600)
        XCTAssertTrue(ChunkSpeechGate.hasSpeech(voiced, threshold: 0.005))
        XCTAssertFalse(ChunkSpeechGate.hasSpeech(silent, threshold: 0.005))
    }

    func testVoiceInOneWindowSurvivesLongQuietTail() {
        let voice = Array(repeating: Float(0.01), count: 1600)
        let quiet = Array(repeating: Float(0), count: 16000)
        XCTAssertTrue(ChunkSpeechGate.hasSpeech(quiet + voice + quiet, threshold: 0.005))
    }

    func testSubThresholdNoiseDoesNotPass() {
        let noise = Array(repeating: Float(0.004), count: 3200)
        XCTAssertFalse(ChunkSpeechGate.hasSpeech(noise, threshold: 0.005))
    }
}
