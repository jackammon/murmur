import Foundation

/// One insertion operation at the active cursor. Implementations own their
/// transport and report whether automatic insertion succeeded (SPEC-052).
@MainActor
public protocol TextInserter {
    @discardableResult
    func insert(_ text: String) -> Bool

    /// Complete an ordered insertion before the next phrase can replace the
    /// clipboard. Clipboard-based implementations need a short settle period.
    @discardableResult
    func insertOrdered(_ text: String) async -> Bool
}

public extension TextInserter {
    @discardableResult
    func insertOrdered(_ text: String) async -> Bool { insert(text) }
}

/// Default append-only insertion. `PasteService` preserves the user's
/// pasteboard and leaves text on it for manual paste if Accessibility fails.
public struct ClipboardPasteInserter: TextInserter {
    public init() {}

    @discardableResult
    public func insert(_ text: String) -> Bool {
        PasteService.paste(text)
    }

    @discardableResult
    public func insertOrdered(_ text: String) async -> Bool {
        guard insert(text) else { return false }
        // CGEvent.post queues ⌘V but does not wait for the target app to read
        // the pasteboard. During stop, decoded phrases can arrive in a burst;
        // pace them so the prior paste sees its own clipboard payload.
        try? await Task.sleep(nanoseconds: 250_000_000)
        return true
    }
}
