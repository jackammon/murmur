import AppKit

/// SPEC-048 — physical Right-Option edges, independent of Left-Option.
enum RightOptionEdge: Equatable {
    case down
    case up
}

struct RightOptionEdgeTracker {
    // kVK_RightOption in the macOS SDK's HIToolbox/Events.h.
    static let keyCode: UInt16 = 0x3D
    // NX_DEVICERALTKEYMASK in IOKit/hidsystem/IOLLEvent.h. The public
    // device-independent `.option` flag stays set if Left-Option is held.
    static let rightOptionMask: UInt = 0x40

    private(set) var isDown = false

    mutating func consume(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> RightOptionEdge? {
        guard keyCode == Self.keyCode else { return nil }
        let nowDown = modifierFlags.rawValue & Self.rightOptionMask != 0
        guard nowDown != isDown else { return nil }
        isDown = nowDown
        return nowDown ? .down : .up
    }

    mutating func reset() -> RightOptionEdge? {
        guard isDown else { return nil }
        isDown = false
        return .up
    }
}

/// Uses the same Accessibility-backed NSEvent monitoring path as fn hotkeys.
/// All access occurs on the main thread, where NSEvent delivers callbacks.
public final class RightOptionHotkeyMonitor: @unchecked Sendable {
    public var onKeyDown: (() -> Void)?
    public var onKeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var tracker = RightOptionEdgeTracker()

    public init() {}

    deinit { removeMonitors() }

    public func setEnabled(_ enabled: Bool) {
        if enabled { installMonitors() }
        else {
            removeMonitors()
            if tracker.reset() != nil { onKeyUp?() }
        }
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.dispatch(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.dispatch(event)
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor); globalMonitor = nil }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
    }

    private func dispatch(_ event: NSEvent) {
        switch tracker.consume(keyCode: event.keyCode, modifierFlags: event.modifierFlags) {
        case .down: onKeyDown?()
        case .up: onKeyUp?()
        case nil: break
        }
    }
}
