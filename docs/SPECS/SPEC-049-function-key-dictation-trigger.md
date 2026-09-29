# SPEC-049 — Function-key dictation trigger

**Status:** implementation in progress
**Owner:** `Sources/MurmurKit/Hotkey/`, `Sources/MurmurApp/`
**Last updated:** 2026-09-27
**Extends:** the existing hotkey implementation

## Goal

Provide a second, configurable press-to-toggle dictation shortcut for the physical microphone/F5 key or a user-managed F5-to-F18 remap, while preserving the primary toggle, Right-Option hold-to-talk, and agent kickoff bindings.

## Behavior

- A separate `KeyboardShortcuts` binding defaults to plain F5. Its key-down runs the same normal dictation toggle action as the primary shortcut. The Shortcut pane provides a recorder to rebind or clear it; F18 can be selected when the physical mic key is remapped externally.
- The app never installs, removes, or changes a HID remap. Settings explains that macOS may consume the physical dictation key and shows the optional `hidutil` F5-to-F18 command. If used, the user selects F18 in the recorder and manages remap persistence themselves.
- The secondary binding is registered after the primary registration (which clears package handlers), alongside agent kickoff. Right-Option monitoring remains independent.
- No dictation mode, microphone, transcription, paste, or privacy behavior changes.

## Acceptance criteria

1. With no custom binding, press F5 once to start Batch dictation and again to stop, on a keyboard where macOS delivers F5 to the app. The primary toggle and Right-Option hold continue working.
2. Set the secondary recorder to F18. Press F18 twice and confirm the same start/stop behavior. Restart the app and confirm the setting persists. Clear the secondary recorder and confirm F18 no longer triggers dictation.
3. Press the agent kickoff shortcut and confirm it still follows its consent and agent path; using the F-key while recording only stops the current recording and does not alter its output mode.
4. On a Mac whose physical mic key is consumed by macOS, optionally apply the shown `hidutil` command outside the app, bind F18, and test the physical key. Removing the external remap is outside this feature.
5. Xcode 16.4 build and full test suite pass. A reviewer manually checks the physical keyboard and focused-app paste target; tests cannot simulate the keyboard's HID delivery.
