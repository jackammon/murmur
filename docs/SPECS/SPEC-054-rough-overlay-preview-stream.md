# SPEC-054 — Rough overlay preview stream

**Status:** implementation in progress
**Owner:** `Sources/MurmurStreaming/`
**Last updated:** 2026-09-27
**Extends:** [SPEC-050](SPEC-050-finalized-streaming-chunks.md)

## Goal

Provide an opt-in, rough live transcript stream for a future Overlay display while keeping finalized chunks and the Batch `finish()` result unchanged.

## Behavior

- After `begin()`, one caller may subscribe with `partialPreview() -> AsyncStream<String>`. A roughly 0.8-second loop inspects only a capped rolling window of the unfinished audio buffer; no preview work starts without a subscriber.
- The preview pass skips windows shorter than 0.8 seconds or with no voice activity above the configured energy threshold. It decodes with `withoutTimestamps`, a pinned language (English fallback), and language detection off. Published text is trimmed and lowercase. Finalized chunk text forms the stable prefix; the current window supplies a replaceable rough suffix.
- Preview decode does not mutate the audio buffer, finalized outcomes, running language, or Batch result. It shares the WhisperKit pipe serially with finalized chunk decoding; a finalized chunk takes priority over a pending preview pass.
- `finish()`, `cancel()`, and a new `begin()` stop the preview stream. Late preview results from an older session are discarded. Failed preview decodes are ignored without failing transcription.
- This slice exposes only the stream. Overlay state, HUD rendering, and paste behavior are separate work.

## Acceptance criteria

1. Synthetic silent and short windows are rejected without decoding. A speech window is capped to the configured rolling duration and receives a pinned language, even when the session did not specify one.
2. The preview delivery unit suppresses duplicate text, ends on cancel, and starts a clean stream on the next session. A late result from an old session is not published.
3. Finalized chunk delivery remains ordered and once-only; `finish()` still assembles Batch text and metadata from finalized outcomes only, including its final tail.
4. Xcode 16.4 build and full tests pass. Synthetic preview policy and delivery tests need no model weights; live preview quality awaits a target-Mac microphone check.
