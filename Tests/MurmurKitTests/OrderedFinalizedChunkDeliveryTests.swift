import XCTest
@testable import MurmurStreaming

final class OrderedFinalizedChunkDeliveryTests: XCTestCase {
    private func chunk(_ start: Int, count: Int = 16000, text: String,
                       succeeded: Bool = true, tail: Bool = false) -> StreamingTranscriber.FinalizedChunk {
        .init(startSample: start, sampleCount: count, text: text,
              detectedLanguage: "en", succeeded: succeeded, isTail: tail)
    }

    func testOutOfOrderChunksEmitOnceInAudioOrderIncludingTail() async {
        var delivery = OrderedFinalizedChunkDelivery()
        delivery.begin()
        let stream = delivery.stream!
        delivery.record(chunk(16000, text: "", succeeded: false))
        delivery.record(chunk(32000, text: "final", tail: true))
        delivery.record(chunk(0, text: "first"))
        delivery.record(chunk(0, text: "duplicate"))
        delivery.finish()

        var received: [StreamingTranscriber.FinalizedChunk] = []
        for await item in stream { received.append(item) }
        XCTAssertEqual(received.map(\.startSample), [0, 16000, 32000])
        XCTAssertEqual(received.map(\.text), ["first", "", "final"])
        XCTAssertFalse(received[1].succeeded)
        XCTAssertTrue(received[2].isTail)
        XCTAssertEqual(received[2].audioSeconds, 1)
    }

    func testCancelDropsPendingChunkAndEndsStream() async {
        var delivery = OrderedFinalizedChunkDelivery()
        delivery.begin()
        let stream = delivery.stream!
        delivery.record(chunk(16000, text: "pending"))
        delivery.cancel()
        delivery.record(chunk(0, text: "late"))

        var received: [StreamingTranscriber.FinalizedChunk] = []
        for await item in stream { received.append(item) }
        XCTAssertTrue(received.isEmpty)
    }

    func testNewSessionEndsOldStreamAndStartsAtZero() async {
        var delivery = OrderedFinalizedChunkDelivery()
        delivery.begin()
        let old = delivery.stream!
        delivery.record(chunk(0, text: "old"))
        delivery.record(chunk(32000, text: "old pending"))
        delivery.begin()
        let new = delivery.stream!
        delivery.record(chunk(0, text: "new"))
        delivery.finish()

        var oldItems: [String] = []
        for await item in old { oldItems.append(item.text) }
        var newItems: [String] = []
        for await item in new { newItems.append(item.text) }
        XCTAssertEqual(oldItems, ["old"])
        XCTAssertEqual(newItems, ["new"])
    }

    func testFinishWithNoTailDoesNotInventItem() async {
        var delivery = OrderedFinalizedChunkDelivery()
        delivery.begin()
        let stream = delivery.stream!
        delivery.record(chunk(0, text: "whole"))
        delivery.finish()

        var received: [StreamingTranscriber.FinalizedChunk] = []
        for await item in stream { received.append(item) }
        XCTAssertEqual(received.count, 1)
        XCTAssertFalse(received[0].isTail)
    }
}
