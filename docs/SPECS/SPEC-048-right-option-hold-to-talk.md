# SPEC-048 — Right-Option hold-to-talk

**Status:** implementation in progress
**Owner:** `Sources/MurmurKit/Hotkey/`, `Sources/MurmurApp/`
**Last updated:** 2026-09-27
**Extends:** the existing hotkey implementation

## Goal

Offer an opt-in, one-key hold-to-talk trigger for Batch dictation without changing the existing toggle hotkey or agent kickoff binding.

## Behavior

- Settings → Shortcut has a Right-Option hold-to-talk switch, off by default. Changing it installs or removes the monitor immediately and persists across relaunch.
- A global `flagsChanged` monitor handles only the hardware Right-Option key code (61). Its edge tracker uses the right-side modifier bit, so Left-Option alone is ignored and holding Left-Option does not hide Right-Option release.
- One down edge requests normal dictation capture; one up edge ends only the recording that Right-Option started. Duplicate changes do not start or stop twice. A release during asynchronous startup cancels the pending hold so recording cannot remain on after the key is up.
- Right-Option never initiates agent kickoff. If another trigger owns a recording, Right-Option release does not stop it. Existing toggle hotkey, fn binding, and kickoff behavior remain available.
- This monitor needs Accessibility permission for global keyboard events, as the existing fn monitor does. Settings explains the need and preserves the toggle fallback.

## Acceptance criteria

1. With the switch off, Right-Option does nothing. With it on and Accessibility granted, hold Right-Option to start normal dictation; release to stop. Repeating the hold creates exactly one recording cycle per physical hold.
2. Left-Option alone does nothing. Hold Left-Option, press and release Right-Option, then release Left-Option: one down and one up action occur at Right-Option edges.
3. Release Right-Option quickly while microphone permission or model startup is pending: no recording remains active. Disable the switch during a hold: the active hold ends.
4. A recording begun with the toggle or agent kickoff hotkey is not ended by Right-Option release. The existing hotkeys still work when the switch is off and on.
5. Restart the app and confirm the switch retains its state. Verify the unavailable-permission guidance and toggle fallback when Accessibility is absent.
6. The monitor edge-state unit tests and full Swift build/test suite pass with Xcode 16.4. Live keyboard and microphone checks require manual testing on the target Mac.
