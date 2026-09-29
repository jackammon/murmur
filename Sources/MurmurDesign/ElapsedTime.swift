import Foundation

/// Recording clock text, e.g. "0:07" or "12:45".
public enum ElapsedTime {
    public static func format(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// Spoken form for VoiceOver, e.g. "1 minute 5 seconds".
    public static func spoken(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.isFinite ? seconds : 0))
        let minutes = whole / 60
        let secs = whole % 60
        let secText = secs == 1 ? "1 second" : "\(secs) seconds"
        guard minutes > 0 else { return secText }
        let minText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return secs == 0 ? minText : "\(minText) \(secText)"
    }
}
