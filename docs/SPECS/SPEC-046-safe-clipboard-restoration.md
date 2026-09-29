# SPEC-046 — Safe clipboard restoration

## Goal

Dictation paste must preserve the user's clipboard, including rich pasteboard data, without replacing a newer copy made while a paste is in flight. Ordered inline phrases must share one clipboard snapshot and restore it once after the last phrase.

## Scope

- Snapshot all pasteboard item types before writing dictation text.
- Restore only when the pasteboard change count still matches the app's last write.
- Provide a sequential session for multiple phrase pastes. A user clipboard change during the session becomes the new restoration target at the next phrase.
- When Accessibility is unavailable, leave the transcript on the clipboard for manual paste.

## Acceptance criteria

- A single successful paste restores the original clipboard after the paste delay, including non-text data.
- Copying something else before restoration leaves that newer copy intact.
- Two quick successful pastes restore the pre-session clipboard once, after the final paste.
- During a sequential session, a user copy between phrases is restored after the last paste; a user copy after the last paste stays intact.
- With Accessibility denied, the transcript remains available for manual paste.

## Validation

Unit-test clipboard ownership decisions. Manually verify copy/paste in TextEdit and a rich-content clipboard source after an app build on the target Mac. Verify the sequential path when Inline mode is wired.
