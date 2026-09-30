import AppKit
import ApplicationServices
import Foundation

///
/// Pasteboard + simulated ⌘V is the standard idiom on macOS for "type this
/// somewhere"; it works in 99 % of apps without Accessibility-tree poking.
/// The simulated keystroke does require Accessibility permission; if missing,
/// `paste` returns false and the caller should fall back to clipboard-only
/// behaviour (the text is already on the pasteboard at that point, so the
/// user can ⌘V manually).
public enum PasteService {
    public enum AccessibilityPermissionState: Equatable {
        case notGranted
        case requiresRelaunch
        case ready
    }

    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        init(_ pasteboard: NSPasteboard) {
            self.init(items: pasteboard.pasteboardItems ?? [])
        }

        init(items: [NSPasteboardItem]) {
            self.items = items.map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                })
            }
        }

        func restoredItems() -> [NSPasteboardItem] {
            items.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            let restored = restoredItems()
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
        }
    }

    private struct PendingRestore {
        var snapshot: Snapshot
        var changeCount: Int
        var generation: UInt64
        var didWrite: Bool
    }

    private static var pending: PendingRestore?
    private static var generation: UInt64 = 0
    private static var sequential = false

    /// Keep one clipboard snapshot across ordered phrase pastes.
    public static func beginSequentialSession() {
        precondition(Thread.isMainThread)
        let pb = NSPasteboard.general
        if pending == nil {
            pending = PendingRestore(snapshot: Snapshot(pb), changeCount: pb.changeCount,
                                     generation: generation, didWrite: false)
        }
        sequential = true
    }

    /// Restore after the final phrase has reached the target application.
    public static func endSequentialSession(restoreDelay: TimeInterval = 0.6) {
        precondition(Thread.isMainThread)
        sequential = false
        if pending?.didWrite == false {
            pending = nil
            return
        }
        scheduleRestore(after: restoreDelay)
    }

    /// Writes `text` to the system pasteboard and posts a synthetic ⌘V at the
    /// HID event tap so the focused app receives a paste. Restores the previous
    /// pasteboard contents after `restoreDelay` if no newer clipboard write
    /// occurred.
    ///
    /// - Returns: `true` if both the pasteboard write and the keystroke succeeded.
    ///   `false` means Accessibility permission is missing — the text is on the
    ///   pasteboard but the user must press ⌘V themselves.
    @discardableResult
    public static func paste(_ text: String, restoreDelay: TimeInterval = 0.6) -> Bool {
        precondition(Thread.isMainThread)
        let pb = NSPasteboard.general

        // A user copy since our last write becomes the new restoration target.
        // Consecutive app-owned pastes keep the original snapshot.
        if pending == nil || pending?.changeCount != pb.changeCount {
            pending = PendingRestore(snapshot: Snapshot(pb), changeCount: pb.changeCount,
                                     generation: generation, didWrite: false)
        }

        pb.clearContents()
        pb.setString(text, forType: .string)

        generation &+= 1
        pending?.changeCount = pb.changeCount
        pending?.generation = generation
        pending?.didWrite = true

        guard isAccessibilityTrusted() else {
            pending = nil  // leave the text available for manual paste
            return false
        }

        guard postCommandV() else {
            pending = nil
            return false
        }

        if !sequential { scheduleRestore(after: restoreDelay) }
        return true
    }

    /// Pasteboard-only — for "Copy" buttons / fallback paths.
    public static func copyToClipboard(_ text: String) {
        precondition(Thread.isMainThread)
        pending = nil
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private static func scheduleRestore(after delay: TimeInterval) {
        guard let expected = pending, !sequential else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let current = pending,
                  current.generation == expected.generation else { return }
            let pb = NSPasteboard.general
            if shouldRestoreClipboard(expectedChangeCount: current.changeCount,
                                      actualChangeCount: pb.changeCount) {
                current.snapshot.restore(to: pb)
            }
            pending = nil
        }
    }

    static func shouldRestoreClipboard(expectedChangeCount: Int, actualChangeCount: Int) -> Bool {
        expectedChangeCount == actualChangeCount
    }

    @discardableResult
    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            requestAccessibilityAccess()
        }
        return accessibilityPermissionState() == .ready
    }

    public static func accessibilityPermissionState() -> AccessibilityPermissionState {
        accessibilityPermissionState(
            accessibilityTrusted: AXIsProcessTrusted(),
            eventPostingAllowed: CGPreflightPostEventAccess()
        )
    }

    static func accessibilityPermissionState(
        accessibilityTrusted: Bool,
        eventPostingAllowed: Bool
    ) -> AccessibilityPermissionState {
        if eventPostingAllowed {
            return .ready
        }
        return accessibilityTrusted ? .requiresRelaunch : .notGranted
    }

    @discardableResult
    public static func requestAccessibilityAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// Open System Settings → Privacy & Security → Accessibility, scrolled to
    /// our entry. Useful for the "permission missing" CTA.
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - private

    private static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09  // virtual keycode for "V"
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
