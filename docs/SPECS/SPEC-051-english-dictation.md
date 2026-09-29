# SPEC-051 — English decoding for the dictation fork

## Goal

Every app dictation path decodes English speech as English without automatic language detection. The setting must accurately describe the app's behavior.

## Scope

- Pin `en` at the app orchestration boundary for offline, streaming, and any configured remote transcription path.
- Show English as the fixed transcription language in Settings. Ignore a legacy saved `language` value from the upstream app.
- Keep the reusable engine and language policy able to decode other languages for CLI and benchmark callers.

## Acceptance criteria

- The app supplies `en` to both the offline engine and `StreamingTranscriber.begin` for every recording, regardless of the old saved language preference.
- The shared decode policy yields `language = en` and `detectLanguage = false` for offline and streaming chunks with that pin.
- Settings shows the active English policy without an auto-detect or other language picker.
- Xcode 16.4 build and tests pass.

## Validation

Run the language policy unit tests and the full test suite. Inspect both app transcription call sites. Confirm the language label in Settings when the app is launched.
