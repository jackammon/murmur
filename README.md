# Murmur

Murmur is a local-first macOS menu bar dictation app. Speak, and your words appear where you are typing.

- **Batch** transcribes a complete recording and pastes the finished text when you stop.
- **Overlay** shows a rough transcript while you speak and pastes the cleaned result when you stop.
- **Inline** pastes finalized phrases as you speak.

Transcription runs on the Mac in the default app flow. Microphone and Accessibility permissions are needed for recording and automatic paste.

## Build and test

The app has been built on macOS 15 with Xcode 16.4. It is currently for local development; a signed distribution release is not configured.

```sh
DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer swift test
bash scripts/wrap_app.sh
open build/Murmur.app
```

See [development instructions](docs/DEVELOPMENT.md) and the [current status](docs/LOCAL-FORK-STATUS.md).

## Troubleshooting

If recording does not start, check Microphone permission in System Settings. If text does not appear at the cursor, check Accessibility permission and try pasting manually. After rebuilding an ad-hoc signed app, macOS may ask for these permissions again.
