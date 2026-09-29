# SPEC-047 — Direct menu bar popover controls

**Status:** implementation in progress
**Owner:** `Sources/MurmurApp/`
**Last updated:** 2026-09-27

## Goal

Let someone start or stop dictation, open Settings, and quit from the left-click menu bar popover without discovering the hotkey or right-click menu.

## Behavior

- Show a primary **Start Dictation** button while idle, ready, or in an error state. It uses the existing dictation recording path and its model and microphone checks. Close the popover on start so the previous app keeps focus.
- Show **Stop Dictation** while recording. Stopping follows the existing transcribe and paste path, including the recording mode chosen when capture began. Close the popover before transcription so it does not retain focus at paste time.
- Disable the recording button during model warming, recording startup, transcription, and polishing. Its label describes the current operation.
- Show **Settings…** and **Quit Murmur** in the popover. These use the same actions as the right-click menu. Opening Settings closes the popover.
- Preserve the right-click menu, hotkey behavior, Batch dictation output, and privacy checks.

## Acceptance criteria

1. Left-click the duck while ready: the popover shows Start Dictation, Settings…, and Quit Murmur. Start Dictation starts a normal dictation capture and closes the popover. Reopen it to use Stop Dictation; that ends capture and closes the popover. The resulting transcript follows the configured paste or clipboard path in the previously focused app.
2. During warming, startup, transcription, and polishing, the recording control is disabled and cannot start another capture.
3. Opening Settings from the popover brings the existing Settings window forward and closes the popover. Quit Murmur terminates the app.
4. The right-click menu and hotkey still work as before. A recording started by the agent kickoff hotkey retains its output mode if stopped through the popover.
5. Build and tests pass with the supported Xcode toolchain. Reviewers manually exercise the popover actions in a wrapped app because the SwiftPM test target does not import the executable UI target.
