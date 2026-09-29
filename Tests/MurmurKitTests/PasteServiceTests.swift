import XCTest
import AppKit
@testable import MurmurKit

final class PasteServiceTests: XCTestCase {
    func testRestoresOnlyWhileAppStillOwnsClipboard() {
        XCTAssertTrue(PasteService.shouldRestoreClipboard(expectedChangeCount: 12, actualChangeCount: 12))
        XCTAssertFalse(PasteService.shouldRestoreClipboard(expectedChangeCount: 12, actualChangeCount: 13))
    }

    func testSnapshotRestoresRichItems() {
        let item = NSPasteboardItem()
        let richType = NSPasteboard.PasteboardType.rtf
        let richData = Data("{\\rtf1 rich}".utf8)
        item.setString("rich", forType: .string)
        item.setData(richData, forType: richType)

        let snapshot = PasteService.Snapshot(items: [item])
        let restored = snapshot.restoredItems()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.string(forType: .string), "rich")
        XCTAssertEqual(restored.first?.data(forType: richType), richData)
    }
}
