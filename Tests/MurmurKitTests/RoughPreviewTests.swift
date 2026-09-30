import XCTest
@testable import MurmurStreaming

final class RoughPreviewTests: XCTestCase {
    func testPolicyRejectsShortAndSilentWindows() {
        let policy = RoughPreviewPolicy(sampleRate: 16000, windowSeconds: 2, energyThreshold: 0.02)
        XCTAssertNil(policy.input(from: Array(repeating: 0.5, count: 8000), pinnedLanguage: "en"))
        XCTAssertNil(policy.input(from: Array(repeating: 0, count: 16000), pinnedLanguage: "en"))
    }

    func testPolicyCapsRollingWindowAndPinsLanguage() {
        let policy = RoughPreviewPolicy(sampleRate: 16000, windowSeconds: 2, energyThreshold: 0.02)
        let audio = Array(repeating: Float(0), count: 32000)
            + Array(repeating: Float(0.5), count: 48000)
        let input = policy.input(from: audio, pinnedLanguage: "fr")
        XCTAssertEqual(input?.samples.count, 32000)
        XCTAssertEqual(input?.language, "fr")
        XCTAssertEqual(policy.input(from: audio, pinnedLanguage: nil)?.language, "en")
    }

    func testPreviewAcceptsSpeechBelowChunkCutThreshold() {
        let quietVoice = Array(repeating: Float(0.01), count: 16000)
        let previewGate = RoughPreviewPolicy(sampleRate: 16000, windowSeconds: 2,
                                             energyThreshold: 0.005)
        let cutPointGate = RoughPreviewPolicy(sampleRate: 16000, windowSeconds: 2,
                                              energyThreshold: 0.02)
        XCTAssertNotNil(previewGate.input(from: quietVoice, pinnedLanguage: "en"))
        XCTAssertNil(cutPointGate.input(from: quietVoice, pinnedLanguage: "en"))
    }

    func testDeliverySuppressesDuplicatesAndRejectsOldSession() async {
        var delivery = RoughPreviewDelivery()
        delivery.begin(generation: 1)
        let old = delivery.stream!
        delivery.record("hello", generation: 1)
        delivery.record("hello", generation: 1)
        delivery.begin(generation: 2)
        let current = delivery.stream!
        delivery.record("late old preview", generation: 1)
        delivery.record("new", generation: 2)
        delivery.finish()

        var oldTexts: [String] = []
        for await text in old { oldTexts.append(text) }
        var currentTexts: [String] = []
        for await text in current { currentTexts.append(text) }
        XCTAssertEqual(oldTexts, ["hello"])
        XCTAssertEqual(currentTexts, ["new"])
    }

    func testCancelEndsPreviewStream() async {
        var delivery = RoughPreviewDelivery()
        delivery.begin(generation: 1)
        let stream = delivery.stream!
        delivery.cancel()
        delivery.record("late", generation: 1)
        var received: [String] = []
        for await text in stream { received.append(text) }
        XCTAssertTrue(received.isEmpty)
    }
}
