# SPEC-056 — First-run model download handoff

## Goal

Closing onboarding during the speech model download must not start a second download of the same Hugging Face cache files.

## Behavior

- Onboarding retains its active download task and lets it finish after the window closes.
- The close callback waits for that task to settle before asking AppDelegate to warm the engine. If the transfer succeeds, its model-ready callback may already start warming; the existing warm deduplication applies.
- If the transfer fails, the warm path can retry once against the incomplete cache and surface an error in the menu bar state.

## Acceptance criteria

1. Closing onboarding at partial progress does not overlap `ensureDownloaded` calls for the same model.
2. Once the download finishes, the engine warms and the menu bar returns to Ready without relaunching.
3. A failed download is shown as an error or an actionable retry path, not a permanently stuck progress indicator.
4. Xcode 16.4 build and tests pass; verify by closing onboarding during a model download on the target Mac.

## Validation

Review the retained download task and close callback ordering, then manually close the onboarding window at partial progress and observe the app's state. The first-run race needs this live check because the Hugging Face staging-file move is outside the app's test harness.
