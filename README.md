# Murmur

<p align="center">
  <img src="assets/murmur-icon.png" alt="Murmur app icon" width="144">
</p>

![Live dictation in Batch, Overlay, and Inline modes](assets/murmur-demo.gif)

Murmur is a local macOS menu bar dictation app. Speak, and your words appear where you are typing.

- **Batch** transcribes a complete recording and pastes the finished text when you stop.
- **Overlay** shows a rough transcript while you speak and pastes the cleaned result when you stop.
- **Inline** pastes finalized phrases as you speak.

Transcription and transcript handling always run on this Mac; audio and transcript text stay on-device. Internet access is used to download speech and polish models and to check for and download app updates. Microphone and Accessibility permissions are needed for recording and automatic paste.

## Install

The easiest free option is to build Murmur on your own Mac. You need macOS 15 or newer and Xcode 16.4 or newer. From Terminal:

```sh
git clone https://github.com/jackammon/murmur.git
cd murmur
bash scripts/package_dmg.sh
```

The script builds Murmur and signs it locally with an ad-hoc signature; no paid Apple developer account is needed. It creates `build/Murmur-<version>.dmg`. Open the image and drag Murmur to Applications, then launch it. Allow Microphone access for recording and Accessibility access for automatic paste in System Settings → Privacy & Security. The first launch downloads the selected speech model; it stays on your Mac and transcription runs offline.

To install from Terminal instead of dragging in Finder, copy the app built by the script into your user Applications folder and launch it:

```sh
mkdir -p "$HOME/Applications"
ditto build/Murmur.app "$HOME/Applications/Murmur.app"
open "$HOME/Applications/Murmur.app"
```

An agent can run these build and install commands on your Mac if it has Terminal access. macOS still requires you to approve Microphone and Accessibility access yourself.

Ad-hoc signatures are meant for local builds. If you share a DMG built on your Mac, Gatekeeper may block it on someone else's Mac. A drag-to-install download needs a Developer ID signature and Apple notarization. Until I can cover Apple's $99 Developer Program fee, you'll need to build Murmur locally using the steps above. If you'd like to contribute toward the fee, I can make a ready-to-install download.

If macOS says the locally built app cannot be opened, Control-click Murmur in Applications, choose **Open**, then confirm **Open**. This exception is for a build you compiled yourself from this repository; don’t use it to approve an app from an unknown source.

## Development

The app has been built on macOS 15 with Xcode 16.4. `scripts/wrap_app.sh` creates a locally signed app bundle; `scripts/package_dmg.sh` packages it for installation on the Mac that built it.

```sh
DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer swift test
bash scripts/wrap_app.sh
open build/Murmur.app
```

## Troubleshooting

If recording does not start, check Microphone permission in System Settings. If text does not appear at the cursor, check Accessibility permission and try pasting manually. After rebuilding an ad-hoc signed app, macOS may ask for these permissions again.

If Accessibility is enabled but Murmur still reports auto-paste as off, repeated ad-hoc builds may have left a grant for an older build. For more stable local permissions across rebuilds, create a self-signed code-signing certificate named `Murmur Dev` in Keychain Access (Certificate Assistant → Create a Certificate; choose **Self-Signed Root** and **Code Signing**), then package with:

```sh
MURMUR_SIGN_IDENTITY="Murmur Dev" bash scripts/package_dmg.sh
```

Remove the old Murmur entry from Accessibility, install the newly signed app, and grant that copy. This self-signed certificate is only for local development; it does not replace Developer ID signing or notarization for distributing a prebuilt app.
