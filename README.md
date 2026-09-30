<div align="center">
  <img src="assets/murmur-icon.png" alt="Murmur app icon" width="96">
  <h1>Murmur</h1>
  <p><strong>Private, on-device dictation for Mac.</strong></p>
  <p>
    <a href="#install">Install</a> ·
    <a href="#building-from-source">Building from source</a> ·
    <a href="#troubleshooting">Troubleshooting</a>
  </p>
</div>

https://github.com/user-attachments/assets/f83903d6-c298-4e09-b4e3-de9c059b0df6

Murmur is a small Mac menu bar app that turns your voice into text wherever your cursor is. Press a shortcut, talk, and your words appear. Transcription runs locally on your Mac with WhisperKit. No account, no subscription, and your audio never leaves your computer.

- **Batch** pastes the full transcript when you stop.
- **Overlay** shows a live draft, then pastes the cleaned transcript.
- **Inline** pastes finalized phrases as you speak.

Optionally, a small local LLM (Gemma 4) can clean up filler words, punctuation, and grammar before pasting. Murmur also tracks how much you dictate and how much time you save compared with typing.

Microphone and Accessibility permissions are needed for recording and automatic paste.

There's no one-click download yet. Shipping a signed, notarized Mac app needs Apple's $99/year developer membership. If you'd like to chip in toward that, I'll happily put together an easy installer. Until then, the steps below take a few minutes.

## Install

Murmur supports macOS 14 or newer. Building requires Xcode 16 or newer with Swift 6.0+. Xcode 16.2 is the newest release that runs on macOS 14.

Before the first build, set up a stable local signing identity. This prevents macOS from treating every rebuild as a different app and discarding its Microphone and Accessibility grants:

1. Open Xcode → Settings → Accounts and add your Apple ID.
2. Select the account, choose Manage Certificates, and create an Apple Development certificate.
3. Verify that `security find-identity -v -p codesigning` lists it.

Then install from Terminal:

```sh
git clone https://github.com/jackammon/murmur.git
cd murmur
bash scripts/install.sh
```

The installer builds and signs Murmur, replaces `~/Applications/Murmur.app`, verifies the signature, and launches it. A free Apple ID is sufficient for a local Apple Development certificate; a paid Developer Program membership is only needed to distribute a notarized build to other Macs.

If no signing identity is available, the installer stops before building and explains how to add one. For a one-off build where permission resets are acceptable, explicitly allow ad-hoc signing:

```sh
MURMUR_ALLOW_ADHOC=1 bash scripts/install.sh
```

On first launch, Murmur guides you through Microphone and Accessibility access. On macOS versions where Accessibility becomes enabled before synthetic paste events become active, Murmur shows a Restart button and resumes onboarding after relaunch. You can also continue without automatic paste; transcripts remain on the clipboard.

The speech model has two first-run stages: Downloading saves the model weights, then Preparing loads the tokenizer and compiles the model for the Mac. Murmur reports it as ready only after both stages finish. The files live under `~/Library/Application Support/Murmur`; Murmur does not probe or migrate a cache in Documents.

To build a DMG instead, run `bash scripts/package_dmg.sh`. Sharing it with another Mac still requires Developer ID signing and Apple notarization.

### Clean uninstall

Remove only the app:

```sh
bash scripts/uninstall.sh
```

For a fresh-install test, remove the app plus downloaded models, history, settings, caches, and permission grants:

```sh
bash scripts/uninstall.sh --all-data
```

## Building from source

The app is tested on macOS 14 and newer with Swift 6.0+. `scripts/wrap_app.sh` creates a signed app bundle, `scripts/install.sh` installs it locally, and `scripts/package_dmg.sh` packages it as a disk image.

```sh
swift test
bash scripts/wrap_app.sh
open build/Murmur.app
```

## Troubleshooting

If recording does not start, check the Permissions section in Murmur Settings and System Settings → Privacy & Security → Microphone. If text does not appear at the cursor, check Accessibility in the same section. When Murmur says a restart is required, use the onboarding Restart button or quit and reopen the app once.

If permissions reset after every rebuild, check the signature requirement:

```sh
codesign -dr - "$HOME/Applications/Murmur.app"
```

An output containing only `cdhash` is an ad-hoc signature. Run the normal installer after adding an Apple Development certificate. A self-signed Code Signing certificate named `Murmur Dev` is also supported for local use, but it does not replace Developer ID signing or notarization for distribution.
