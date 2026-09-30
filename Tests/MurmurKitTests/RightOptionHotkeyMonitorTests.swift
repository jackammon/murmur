import XCTest
import AppKit
@testable import MurmurKit

final class RightOptionHotkeyMonitorTests: XCTestCase {
    private let rightFlag = NSEvent.ModifierFlags(rawValue: RightOptionEdgeTracker.rightOptionMask)

    func testOneDownAndUpPerHold() {
        var tracker = RightOptionEdgeTracker()
        XCTAssertEqual(tracker.consume(keyCode: 61, modifierFlags: rightFlag), .down)
        XCTAssertNil(tracker.consume(keyCode: 61, modifierFlags: rightFlag))
        XCTAssertEqual(tracker.consume(keyCode: 61, modifierFlags: []), .up)
        XCTAssertNil(tracker.consume(keyCode: 61, modifierFlags: []))
    }

    func testLeftOptionAloneNeverFires() {
        var tracker = RightOptionEdgeTracker()
        XCTAssertNil(tracker.consume(keyCode: 58, modifierFlags: .option))
        XCTAssertNil(tracker.consume(keyCode: 58, modifierFlags: []))
        XCTAssertFalse(tracker.isDown)
    }

    func testRightReleaseWithLeftOptionStillHeld() {
        var tracker = RightOptionEdgeTracker()
        XCTAssertEqual(tracker.consume(keyCode: 61, modifierFlags: [.option, rightFlag]), .down)
        XCTAssertEqual(tracker.consume(keyCode: 61, modifierFlags: .option), .up)
    }

    func testDisableSynthesizesOneRelease() {
        var tracker = RightOptionEdgeTracker()
        XCTAssertEqual(tracker.consume(keyCode: 61, modifierFlags: rightFlag), .down)
        XCTAssertEqual(tracker.reset(), .up)
        XCTAssertNil(tracker.reset())
    }
}
