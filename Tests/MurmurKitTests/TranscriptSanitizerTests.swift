import XCTest
@testable import MurmurKit

final class TranscriptSanitizerTests: XCTestCase {
    func testRemovesCanonicalBlankAudioVariants() {
        for marker in [
            "[BLANK_AUDIO]",
            "[ blank audio ]",
            "[blank-audio]",
            "(blank_audio)",
            "<|nospeech|>",
        ] {
            XCTAssertEqual(TranscriptSanitizer.sanitize(marker), "")
        }
    }

    func testRemovesNonSpeechAnnotations() {
        for marker in [
            "[silence]",
            "(no speech)",
            "[no_audio]",
            "[inaudible]",
            "[unintelligible]",
            "[noise]",
            "[background noise]",
            "[music]",
            "[applause]",
            "[laughter]",
        ] {
            XCTAssertEqual(TranscriptSanitizer.sanitize(marker), "")
        }
    }

    func testRemovesEmbeddedAnnotationsWithoutDroppingSpeech() {
        XCTAssertEqual(
            TranscriptSanitizer.sanitize("hello [BLANK_AUDIO] world (laughter)"),
            "hello world"
        )
    }

    func testDropsPunctuationAndMusicSymbolsWithoutWords() {
        XCTAssertEqual(TranscriptSanitizer.sanitize("… ♪♪♪ ?!"), "")
    }

    func testPreservesLegitimateBracketedSpeech() {
        XCTAssertEqual(
            TranscriptSanitizer.sanitize("Use [draft] in the filename"),
            "Use [draft] in the filename"
        )
    }

    func testPreservesOrdinaryShortPhrases() {
        for phrase in ["thank you", "bye", "you", "okay"] {
            XCTAssertEqual(TranscriptSanitizer.sanitize(phrase), phrase)
        }
    }
}
