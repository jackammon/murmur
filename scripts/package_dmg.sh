#!/usr/bin/env bash
# Build Murmur.app and package it as a drag-to-Applications disk image.
#
# Usage: bash scripts/package_dmg.sh
#        MURMUR_SIGN_IDENTITY="Developer ID Application: ..." bash scripts/package_dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/wrap_app.sh"

APP="$ROOT/build/Murmur.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/build/Murmur-$VERSION.dmg"

codesign --verify --deep --strict --verbose=2 "$APP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" | grep -qx 'com.jackammon.murmur'

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Murmur.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "Murmur $VERSION" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG"

SIGNING_IDENTITY="$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
    echo "→ Signing disk image: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
elif [[ -n "${MURMUR_NOTARY_PROFILE:-}" ]]; then
    echo "error: notarization requires a Developer ID Application signed app and disk image" >&2
    exit 1
else
    echo "→ Skipping disk image signature (no Developer ID Application identity)"
fi

if [[ -n "${MURMUR_NOTARY_PROFILE:-}" ]]; then
    echo "→ Submitting disk image for notarization..."
    xcrun notarytool submit "$DMG" --keychain-profile "$MURMUR_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

hdiutil verify "$DMG"

echo "✓ $DMG"
echo "  App signature: $(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^Signature=//p')"
echo "  Disk image signature: $(codesign -dv --verbose=2 "$DMG" 2>&1 | sed -n 's/^Signature=//p')"
echo "  Bundle ID: com.jackammon.murmur"
