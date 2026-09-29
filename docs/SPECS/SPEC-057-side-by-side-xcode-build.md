# SPEC-057 — Side-by-side Xcode build

## Goal

Build the fork with Xcode 16.4 on macOS 15 without changing the system-wide developer directory or requiring an OS upgrade.

## Behavior

- `scripts/wrap_app.sh` respects an explicit `DEVELOPER_DIR`.
- If none is set and `/Applications/Xcode_16.4.app` is installed, the script selects that toolchain for its SwiftPM and icon commands.
- Other machines retain the script's existing selected-Xcode/CommandLineTools fallback.

## Acceptance criteria

1. With Xcode 16.4 side by side and Xcode 16.2 selected globally, `bash scripts/wrap_app.sh` builds and verifies the app bundle.
2. An explicit `DEVELOPER_DIR` remains authoritative.
3. `xcode-select -p` and macOS version are unchanged by the build.

## Validation

Run `bash -n scripts/wrap_app.sh` and build once with `DEVELOPER_DIR` unset on this Mac; inspect the toolchain line and verify the produced app's signature.
