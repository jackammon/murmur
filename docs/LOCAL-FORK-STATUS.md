# Murmur development status

Murmur is a local-first macOS dictation app. Batch, Overlay, and Inline modes are implemented. Overlay shows rough text while recording and inserts the final transcript when recording stops.

The app can be built locally on macOS 15 with Xcode 16.4. `scripts/wrap_app.sh` produces `build/Murmur.app` with a local signature. Distribution signing, notarization, a published update feed, and a Homebrew cask are not configured.

The inherited remote transcription, agent, and update code remains in the package but is not reachable from the local dictation UI. See SPEC-055 for the current runtime boundary. The next manual checks are a fresh onboarding download, silence-only Inline dictation, and clipboard restoration when the clipboard changes mid-recording.

The synthetic benchmark references now say Murmur. Regenerate the gitignored audio with `bash bench/corpus/fetch.sh` (and noise clips with `python3 bench/corpus/mix_noise.py`) before benchmarking; older benchmark results used different spoken text and should not be compared directly.

Build and test commands are in [DEVELOPMENT.md](DEVELOPMENT.md).
