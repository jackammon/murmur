# SPEC-052 — Text insertion seam

## Goal

Route dictation output through one replaceable insertion interface so Batch and future Inline phrases use the same clipboard-safe paste behavior.

## Scope

- Add a main-actor `TextInserter` protocol with an `insert(_:)` operation.
- Make `ClipboardPasteInserter` delegate to the existing `PasteService.paste` behavior.
- Route the app's automatic dictation paste and history recovery paste through the inserter. Explicit copy-to-clipboard remains a separate user action.

## Acceptance criteria

- The default inserter reports the underlying paste result and retains its clipboard fallback.
- Batch and history recovery use the same default inserter.
- Tests can substitute an inserter without posting a keyboard event.
- Xcode 16.4 build and tests pass.

## Validation

Unit-test a fake inserter at the interface boundary. Inspect the app paste call sites and manually paste a Batch dictation into a focused editor.
