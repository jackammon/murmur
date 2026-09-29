# SPEC-055 — Local-only dictation runtime

## Goal

The native dictation fork records and transcribes on this Mac. Once speech model weights are cached, launching and dictating does not contact update feeds, remote transcription endpoints, or an agent service.

## Scope

- Force the app runtime to use the local WhisperKit backend even if an upstream installation saved a remote backend preference.
- Remove remote transcription, agent kickoff, and update actions from the fork's visible controls and hotkey registration.
- Do not start Sparkle or the release checker at launch or by opening Settings.
- Keep the speech model download path available for first installation and model changes.
- Remove misleading microphone copy from the bundle.

## Acceptance criteria

1. A saved `transcriptionBackend=remote` preference cannot make this app upload audio; Batch, Overlay, and Inline all use the local engine.
2. Launch and Settings do not schedule an update check. No agent kickoff hotkey is registered.
3. Settings shows local transcription and no remote endpoint, agent kickoff, or update controls.
4. Model weight downloads remain possible with an explicit selected model or first-run setup.
5. Xcode 16.4 build/tests and a static reachable-egress audit pass. Manual launch shows the local-only UI.

## Validation

Inspect launch and hotkey call sites plus the Settings tree; run build/tests. Cache a model, then observe network activity while launching and dictating on the target Mac.
