import Foundation
import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    /// Dictation shortcut. The original binding preserves muscle memory across upgrades.
    static let toggleRecording = Self(
        "murmur.toggleRecording",
        default: .init(.space, modifiers: [.control, .shift])
    )

    /// Physical mic-key shortcut; macOS may report F5 or a remapped F18.
    static let functionKeyRecording = Self(
        "murmur.functionKeyRecording",
        default: .init(.f5)
    )

    /// combo for the lower-frequency / higher-commitment action — the
    /// user is opting into a multi-step background workflow
    /// (consent → spawn → notification → attach), and an ergonomic
    /// launch keeps the cumulative friction tolerable.
    static let agentKickoff = Self(
        "murmur.agentKickoff",
        default: .init(.space, modifiers: [.control])
    )
}

/// Convenience helpers for surfacing the user's current hotkey in copy.
public enum HotkeyDisplay {
    /// Returns the user's bound shortcut as a glyph string ("⌃⇧Space"), or
    /// "your hotkey" if they've cleared it.
    public static var current: String {
        if let fn = FnShortcut.stored {
            return fn.displayLabel
        }
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .toggleRecording) else {
            return "your hotkey"
        }
        let str = "\(shortcut)"
        return str.isEmpty ? "your hotkey" : str
    }
}

public enum HotkeyMode: String, Sendable, CaseIterable {
    /// Press to start; press again to stop.
    case toggle
}

public final class HotkeyManager {
    private let fnMonitor = FnHotkeyMonitor()
    private let rightOptionMonitor = RightOptionHotkeyMonitor()

    public static let rightOptionDefaultsKey = "murmur.rightOptionHoldToTalk"

    public init() {}

    /// Register both keyDown and keyUp handlers. The caller dispatches based
    /// on its current `HotkeyMode` (read at handler-call time so a Settings
    /// change takes effect immediately, no re-register needed).
    ///
    /// If `FnShortcut.stored` is set the fn monitor is used; otherwise the
    /// Carbon-backed `KeyboardShortcuts` path handles the binding. Both paths
    /// fire the same `onKeyDown` / `onKeyUp` callbacks.
    public func register(
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp:   @escaping @MainActor () -> Void
    ) {
        if let fnShortcut = FnShortcut.stored {
            KeyboardShortcuts.removeAllHandlers()
            // FnHotkeyMonitor callbacks are plain () -> Void; dispatch to
            // @MainActor so the caller's contract is preserved.
            fnMonitor.onKeyDown = { Task { @MainActor in onKeyDown() } }
            fnMonitor.onKeyUp   = { Task { @MainActor in onKeyUp() } }
            fnMonitor.setShortcut(fnShortcut)
        } else {
            fnMonitor.setShortcut(nil)
            KeyboardShortcuts.removeAllHandlers()
            KeyboardShortcuts.onKeyDown(for: .toggleRecording) {
                Task { @MainActor in onKeyDown() }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
                Task { @MainActor in onKeyUp() }
            }
        }
    }

    /// Single-handler convenience — kept for any caller that only cares about
    /// toggle-on-press. Equivalent to `register(onKeyDown: action, onKeyUp: {})`.
    public func registerToggle(_ action: @escaping @MainActor () -> Void) {
        register(onKeyDown: action, onKeyUp: {})
    }

    /// support for kickoff is a flagged follow-up in the spec's open
    /// questions. Intended to be called once at app launch, AFTER
    /// `register(...)` — the dictation register clears all handlers, so
    /// kickoff is installed second to survive.
    public func registerKickoff(_ action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .agentKickoff) {
            Task { @MainActor in action() }
        }
    }

    /// Register after `registerToggle`, which clears KeyboardShortcuts
    /// handlers. Both bindings route through the app's same toggle action.
    public func registerFunctionKeyToggle(_ action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .functionKeyRecording) {
            Task { @MainActor in action() }
        }
    }

    /// Register a separate hold-to-talk monitor that shortcut changes leave intact.
    public func registerRightOptionHold(
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp: @escaping @MainActor () -> Void
    ) {
        rightOptionMonitor.onKeyDown = { Task { @MainActor in onKeyDown() } }
        rightOptionMonitor.onKeyUp = { Task { @MainActor in onKeyUp() } }
        setRightOptionHoldEnabled(UserDefaults.standard.bool(forKey: Self.rightOptionDefaultsKey))
    }

    public func setRightOptionHoldEnabled(_ enabled: Bool) {
        rightOptionMonitor.setEnabled(enabled)
    }

    public func unregister() {
        KeyboardShortcuts.removeAllHandlers()
        fnMonitor.setShortcut(nil)
        rightOptionMonitor.setEnabled(false)
    }
}
