import XCTest
@testable import MurmurKit

@MainActor
private final class RecordingInserter: TextInserter {
    var inserted: [String] = []
    var result = false

    func insert(_ text: String) -> Bool {
        inserted.append(text)
        return result
    }
}

final class TextInserterTests: XCTestCase {
    @MainActor
    func testSubstitutableInserterPreservesOrderAndResult() {
        let inserter: RecordingInserter = RecordingInserter()
        let output: any TextInserter = inserter
        XCTAssertFalse(output.insert("First. "))
        inserter.result = true
        XCTAssertTrue(output.insert("Second. "))
        XCTAssertEqual(inserter.inserted, ["First. ", "Second. "])
    }
}
