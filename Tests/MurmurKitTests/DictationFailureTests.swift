import XCTest
@testable import MurmurKit

final class DictationFailureTests: XCTestCase {
    func testMessageDropsTheEngineWrapper() {
        let error = EngineError.runtimeFailed("Speech model failed to load")
        XCTAssertEqual(DictationFailure.message(for: error), "Speech model failed to load")
    }

    func testMessageKeepsOnlyTheFirstLine() {
        let error = EngineError.runtimeFailed("Transcription failed:\ninternal details")
        XCTAssertEqual(DictationFailure.message(for: error), "Transcription failed:")
    }
}
