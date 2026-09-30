import XCTest
@testable import MurmurKit

final class SpeechModelCatalogTests: XCTestCase {
    func testDisplayName_knownVariants() {
        XCTAssertEqual(SpeechModelCatalog.displayName(for: "medium"), "Medium")
        XCTAssertEqual(SpeechModelCatalog.displayName(for: "large-v3"), "Large v3")
        XCTAssertEqual(SpeechModelCatalog.displayName(for: "tiny"), "Tiny")
    }

    func testDisplayName_unknownVariantFallsBackToRaw() {
        XCTAssertEqual(SpeechModelCatalog.displayName(for: "distil-large-v3"), "distil-large-v3")
    }

    func testSizeLabel_knownVariants() {
        XCTAssertEqual(SpeechModelCatalog.sizeLabel(for: "tiny"), "~150 MB")
        XCTAssertEqual(SpeechModelCatalog.sizeLabel(for: "medium"), "~1.5 GB")
        XCTAssertEqual(SpeechModelCatalog.sizeLabel(for: "large-v3"), "~3 GB")
    }

    func testSizeLabel_unknownVariantFallsBack() {
        XCTAssertEqual(SpeechModelCatalog.sizeLabel(for: "mystery"), "the model")
    }

    private func canDelete(
        _ variant: String,
        selected: String = "large-v3",
        loaded: String? = "large-v3",
        dictating: Bool = false
    ) -> Bool {
        SpeechModelCatalog.canDelete(
            variant: variant, selected: selected, loaded: loaded, dictating: dictating
        )
    }

    func testSelectedAndLoadedModelsAreProtected() {
        XCTAssertFalse(canDelete("large-v3"))
        XCTAssertFalse(canDelete("medium", selected: "medium", loaded: "large-v3"))
        XCTAssertTrue(canDelete("small"))
    }

    func testDictationProtectsEveryModel() {
        XCTAssertFalse(canDelete("small", dictating: true))
        XCTAssertFalse(canDelete("large-v3", dictating: true))
    }
}
