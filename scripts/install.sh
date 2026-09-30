#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_PARENT="${MURMUR_INSTALL_DIR:-$HOME/Applications}"
DESTINATION="$INSTALL_PARENT/Murmur.app"

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    elif [[ -d /Applications/Xcode_16.2.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode_16.2.app/Contents/Developer
    fi
fi

case "$INSTALL_PARENT" in
    /*) ;;
    *) echo "error: MURMUR_INSTALL_DIR must be an absolute path." >&2; exit 1 ;;
esac

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if (( MACOS_MAJOR < 14 )); then
    echo "error: Murmur requires macOS 14 or newer." >&2
    exit 1
fi

SWIFT_VERSION="$(swift --version 2>/dev/null | sed -nE '1s/.*Swift version ([0-9]+)\.([0-9]+).*/\1 \2/p')"
read -r SWIFT_MAJOR SWIFT_MINOR <<<"$SWIFT_VERSION"
if [[ -z "${SWIFT_MAJOR:-}" ]] || (( SWIFT_MAJOR < 6 || (SWIFT_MAJOR == 6 && SWIFT_MINOR < 1) )); then
    echo "error: Murmur needs Swift 6.1 or newer; the active toolchain is:" >&2
    swift --version >&2 || true
    echo "Install Xcode 16.3 or newer, then run this script again." >&2
    exit 1
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK_PATH" || ! -d "$SDK_PATH" ]]; then
    echo "error: the full macOS SDK is unavailable. Install and open Xcode once, then rerun this script." >&2
    exit 1
fi

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if ! grep -qE '^[[:space:]]*[1-9][0-9]* valid identities found' <<<"$IDENTITIES" && \
   [[ "${MURMUR_ALLOW_ADHOC:-0}" != "1" ]]; then
    echo "error: no stable code-signing identity is available." >&2
    echo "Add your Apple ID in Xcode → Settings → Accounts and create an Apple Development certificate," >&2
    echo "or create a self-signed Code Signing certificate named 'Murmur Dev' in Keychain Access." >&2
    echo "A stable identity keeps Microphone and Accessibility grants across rebuilds." >&2
    echo "To accept permission resets for a one-off build, rerun with MURMUR_ALLOW_ADHOC=1." >&2
    exit 1
fi

bash "$ROOT/scripts/wrap_app.sh"
codesign --verify --deep --strict "$ROOT/build/Murmur.app"

DESIGNATED_REQUIREMENT="$(codesign -dr - "$ROOT/build/Murmur.app" 2>&1 | sed -n 's/^designated => //p')"
if [[ "$DESIGNATED_REQUIREMENT" == *cdhash* && "${MURMUR_ALLOW_ADHOC:-0}" != "1" ]]; then
    echo "error: the build has an ad-hoc, cdhash-only signature. Refusing to install it because permissions would reset on the next rebuild." >&2
    exit 1
fi

mkdir -p "$INSTALL_PARENT"
STAGING_DIRECTORY="$(mktemp -d "$INSTALL_PARENT/.murmur-install.XXXXXX")"
BACKUP_APP="$INSTALL_PARENT/.Murmur.backup.$$"

restore_backup() {
    if [[ -d "$BACKUP_APP" && ! -e "$DESTINATION" ]]; then
        mv "$BACKUP_APP" "$DESTINATION"
    fi
    if [[ -d "$STAGING_DIRECTORY" ]]; then
        rm -rf "$STAGING_DIRECTORY"
    fi
}
trap restore_backup EXIT

ditto "$ROOT/build/Murmur.app" "$STAGING_DIRECTORY/Murmur.app"
/usr/bin/pkill -x murmur 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    /usr/bin/pgrep -x murmur >/dev/null 2>&1 || break
    /bin/sleep 0.2
done
if /usr/bin/pgrep -x murmur >/dev/null 2>&1; then
    echo "error: Murmur did not quit; the existing app was left unchanged." >&2
    exit 1
fi

if [[ -e "$DESTINATION" ]]; then
    mv "$DESTINATION" "$BACKUP_APP"
fi
mv "$STAGING_DIRECTORY/Murmur.app" "$DESTINATION"
if [[ -d "$BACKUP_APP" ]]; then
    rm -rf "$BACKUP_APP"
fi

open "$DESTINATION"
echo "Installed and opened $DESTINATION"
echo "Signature requirement: $DESIGNATED_REQUIREMENT"
echo "On first launch, finish Microphone and Accessibility setup in Murmur."
echo "The model is ready only after Murmur finishes both Downloading and Preparing."
