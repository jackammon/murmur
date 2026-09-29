import XCTest
@testable import MurmurKit

final class DictationModeTests: XCTestCase {
    func testStoredModeDefaultsSafelyAndRoundTrips() {
        XCTAssertEqual(DictationMode.fromStored(nil), .batch)
        XCTAssertEqual(DictationMode.fromStored(""), .batch)
        XCTAssertEqual(DictationMode.fromStored("unknown"), .batch)
        for mode in DictationMode.allCases {
            XCTAssertEqual(DictationMode.fromStored(mode.rawValue), mode)
        }
    }

    func testInlineCommitsChunksWithoutFinalPaste() {
        XCTAssertTrue(DictationMode.inline.streamsFromStart)
        XCTAssertFalse(DictationMode.inline.pastesFinalTranscript)
        XCTAssertFalse(DictationMode.batch.streamsFromStart)
        XCTAssertTrue(DictationMode.overlay.streamsFromStart)
        XCTAssertTrue(DictationMode.batch.pastesFinalTranscript)
        XCTAssertTrue(DictationMode.overlay.pastesFinalTranscript)
    }

    func testClipboardOnlyPreferencePreventsInsertionInEveryMode() {
        for mode in DictationMode.allCases {
            XCTAssertEqual(mode.outputPlan(autoPasteEnabled: false), .copyFinalTranscript)
        }
        XCTAssertEqual(DictationMode.inline.outputPlan(autoPasteEnabled: true), .insertFinalizedChunks)
        XCTAssertEqual(DictationMode.batch.outputPlan(autoPasteEnabled: true), .pasteFinalTranscript)
        XCTAssertEqual(DictationMode.overlay.outputPlan(autoPasteEnabled: true), .pasteFinalTranscript)
    }
}
