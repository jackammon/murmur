import Foundation

public enum TranscriptSanitizer {
    private static let annotationPattern = #"(?:\[\s*(?:blank[\s_-]*audio|silence|no[\s_-]*(?:speech|audio)|inaudible|unintelligible|(?:background[\s_-]*)?noise|music|applause|laughter)\s*\]|\(\s*(?:blank[\s_-]*audio|silence|no[\s_-]*(?:speech|audio)|inaudible|unintelligible|(?:background[\s_-]*)?noise|music|applause|laughter)\s*\)|<\|nospeech\|>)"#

    private static let annotationRegex = try! NSRegularExpression(
        pattern: annotationPattern,
        options: [.caseInsensitive]
    )
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#)
    private static let alphanumericRegex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]"#)

    public static func sanitize(_ transcript: String) -> String {
        let fullRange = NSRange(transcript.startIndex..., in: transcript)
        let withoutAnnotations = annotationRegex.stringByReplacingMatches(
            in: transcript,
            range: fullRange,
            withTemplate: " "
        )
        let whitespaceRange = NSRange(withoutAnnotations.startIndex..., in: withoutAnnotations)
        let collapsed = whitespaceRegex.stringByReplacingMatches(
            in: withoutAnnotations,
            range: whitespaceRange,
            withTemplate: " "
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let contentRange = NSRange(collapsed.startIndex..., in: collapsed)
        guard alphanumericRegex.firstMatch(in: collapsed, range: contentRange) != nil else {
            return ""
        }
        return collapsed
    }
}
