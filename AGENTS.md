# Contributing to Murmur

## Verification

- Tests are required. Changes to logic need unit coverage; changes to metrics need a benchmark delta documented in the PR; changes to the UI need manual reproduction steps.
- For WhisperKit details, read the checked-out source in `.build/checkouts/argmax-oss-swift/Sources/WhisperKit/Core/`. For benchmark math, read `Sources/MurmurPlatform/WER.swift` and the bench runner.
- PR descriptions should state the change and why, followed by verification.

## Tooling

- Xcode 16.4 or newer for the app build
- macOS 15 or newer for local app development
- Python 3.11+ in `.venv` only when working on the optional Lightning baseline

## Package map

- `MurmurKit`: audio, transcription, hotkeys, polish, and output
- `MurmurPlatform`: diagnostics, shared policies, and benchmark metrics
- `MurmurDesign`: stripe-field geometry, palette, and dither math for the app's visuals (see `docs/DESIGN.md`)
- `MurmurStreaming`: streaming transcription helpers
- `MurmurApp`: menu bar app
- `MurmurCLI`: single-file transcription tool
- `MurmurBench` and other bench targets: accuracy and performance harnesses
- `bench/corpus/`: audio corpus references (large audio files are gitignored)

See `docs/DEVELOPMENT.md` for build commands and `docs/LOCAL-FORK-STATUS.md` for current limitations.
