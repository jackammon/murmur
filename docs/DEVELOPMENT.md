# Developing Murmur

Use Xcode 16.4 or newer on macOS 15 for the app. The package has a macOS 13 minimum because of WhisperKit; the local GUI has been exercised on macOS 15.

```sh
DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer swift test
bash scripts/wrap_app.sh
open build/Murmur.app
```

`wrap_app.sh` selects `/Applications/Xcode_16.4.app` when present and no `DEVELOPER_DIR` is set. It creates a locally signed app bundle. Microphone and Accessibility permissions are needed to record and paste.

The package contains `MurmurKit` (audio, transcription, hotkeys, and output), `MurmurPlatform` (shared diagnostics and metrics), `MurmurStreaming`, the `MurmurApp` menu bar UI, and CLI/bench executables. To transcribe a file or run the benchmark:

```sh
swift run murmur-cli some-audio.wav
swift run murmur-bench --engines whisperkit --models tiny --corpus bench/corpus/short --out /tmp/murmur-bench
```

The benchmark corpus audio is fetched separately with `bash bench/corpus/fetch.sh`. Corpus references and bench scripts live under `bench/`.

Recent implementation decisions are recorded in `docs/SPECS/SPEC-046` through `SPEC-057`. Distribution infrastructure has not been set up for this fork.
