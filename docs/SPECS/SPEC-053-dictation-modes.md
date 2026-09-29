# SPEC-053 — Explicit dictation modes

## Goal

The menu bar app offers Batch, Overlay, and Inline modes. The selected mode is fixed for each recording, so changing Settings mid-recording cannot change how that recording is transcribed or inserted.

## Behavior

- Batch remains the default and pastes one clean transcript after stopping. Short recordings use offline transcription; long recordings retain the existing streaming optimization.
- Overlay displays a readable, labelled floating transcript preview while recording, then pastes one clean transcript on stop. The preview shows a listening placeholder until rough words are available.
- Inline inserts each completed pause-bounded phrase in audio order, including the final tail when recording stops. It does not paste the assembled transcript again.
- The menu bar popover and Settings expose the same persisted mode choice. Changes made during a recording apply to the next recording.
- A silent capture produces no insertion in any mode. Transcription is pinned to English.
- When automatic paste is off, every mode leaves the final assembled transcript on the clipboard and sends no paste keystrokes. The preference is fixed for the recording at start.

## Acceptance criteria

1. A new install starts in Batch. The menu bar and Settings show the selected mode and agree after either changes it.
2. Batch still pastes exactly once after stop and preserves its short/long transcription behavior.
3. Overlay opens a distinct, readable floating preview as soon as recording starts, shows rough words when available, inserts nothing before stop, and pastes once after stop.
4. Inline inserts finalized phrases once each in order, including the tail, and restores the clipboard after the session.
5. Switching modes while recording does not change that recording's output behavior.
6. Turning automatic paste off before an Inline recording prevents phrase insertion and leaves one complete transcript on the clipboard after stop; the same preference works in Batch and Overlay.
7. Xcode 16.4 build and tests pass; live checks in TextEdit verify cursor insertion and microphone/Accessibility behavior.

## Validation

Test mode decoding and session snapshot logic without microphone access. Feed pause-separated audio through the streaming bench for phrase ordering. Verify all three modes with live speech in TextEdit and inspect clipboard preservation, including a user copy during recording.
