# SPEC-050 — Ordered finalized streaming chunks

**Status:** implementation in progress
**Owner:** `Sources/MurmurStreaming/`
**Last updated:** 2026-09-27
**Extends:** the existing streaming transcriber

## Goal

Expose completed, pause-bounded transcription chunks as they finish so a future Inline mode can commit phrases in order. Preserve the existing assembled `finish()` result used by Batch.

## Behavior

- After `begin()`, one consumer may obtain a session-scoped `AsyncStream` of finalized chunks. Each item contains its start sample, audio duration, raw text, detected language, success flag, and whether it was the tail submitted by `finish()`.
- A chunk is emitted only after its transcription completes. Delivery follows audio order and is at most once for each start sample, even if completions arrive out of order. Empty or failed chunks retain their place in the stream so callers can see gaps without confusing later order.
- `finish()` submits the remaining tail, awaits all outcomes, emits it once if present, and finishes the stream. A session ending exactly on a cut boundary finishes the stream without inventing an empty tail.
- `cancel()` ends the stream and discards pending outcomes. A subsequent `begin()` ends the previous stream and starts a new one; late outcomes from the old drain cannot enter the new stream. A `finish()` superseded by cancellation or a new session throws `CancellationError` after its drain wait.
- `finish()` retains its current text stitching, metadata, and failure behavior. No paste or UI wiring is part of this slice.

## Acceptance criteria

1. Given chunks that complete out of order, the delivery unit emits them in increasing start-sample order, once each, including an empty/failed placeholder and a final tail.
2. Cancelling or beginning a new session finishes the old stream and prevents its pending chunks from appearing in the new stream.
3. `finish()` still returns the same Batch transcript assembly and chunk metadata. A nonempty tail is delivered before the stream ends; an empty tail is not emitted.
4. Xcode 16.4 build and test suite pass. Delivery tests use synthetic chunk outcomes and do not require model weights.
