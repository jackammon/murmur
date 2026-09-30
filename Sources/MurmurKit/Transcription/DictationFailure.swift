import Foundation

/// Convert an engine error into a concise message for the menu-bar popover.
/// Remove wrapper text while retaining the actionable error details.
public enum DictationFailure {
    private static let prefixes = [
        "Engine runtime failed: ",
        "Engine load failed: ",
    ]

    public static func message(for error: Error) -> String {
        // Engine errors may include multiline implementation details.
        var line = "\(error)".components(separatedBy: "\n")[0]
            .trimmingCharacters(in: .whitespaces)
        for prefix in prefixes where line.hasPrefix(prefix) {
            line.removeFirst(prefix.count)
        }
        return line.isEmpty ? "Transcription failed." : line
    }

}
