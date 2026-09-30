#!/usr/bin/env bash
# Build the murmur SwiftPM executable and wrap it in a minimal
# Murmur.app bundle under build/.
#
# Signing is picked in this order:
#   1. $MURMUR_SIGN_IDENTITY (explicit override — usually a Developer ID for dist).
#   2. Any "Developer ID Application: ..." identity in the keychain
#      — distribution cert. Hardened runtime + TSA timestamp + entitlements.
#   3. Any "Apple Development: ..." identity in the keychain (free, comes
#      with Xcode + an Apple ID; no paid Developer Program needed).
#      Gives a stable Designated Requirement → TCC keeps the AX/mic grant
#      across rebuilds. Doesn't satisfy Gatekeeper on other Macs.
#   4. "Murmur Dev" if you've created a self-signed code-signing cert
#      with that name. (Keychain Access → Certificate Assistant → Create
#      a Certificate; Self-Signed Root, type Code Signing.) Manual
#      alternative if (3) isn't available.
#   5. Ad-hoc — fallback. Works for local `open`, but each rebuild changes
#      the cdhash so TCC sees a "new" app and re-prompts for permissions.
#
# Usage: bash scripts/wrap_app.sh
#        MURMUR_SIGN_IDENTITY="Developer ID Application: ..." bash scripts/wrap_app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode_16.4.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
    echo "→ Using Xcode toolchain at $DEVELOPER_DIR"
elif [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    echo "→ Using Xcode toolchain at $DEVELOPER_DIR"
elif [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* && -d /Applications/Xcode_16.2.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode_16.2.app/Contents/Developer
    echo "→ Using Xcode toolchain at $DEVELOPER_DIR"
fi

BUNDLE="$ROOT/build/Murmur.app"
BIN_NAME="murmur"
VERSION="$(grep -E 'public static let version' Sources/MurmurPlatform/MurmurPlatform.swift | sed -E 's/.*"([^"]+)".*/\1/')"

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
pick_identity_hash() {
    awk -v prefix="\"$1" 'index($0, prefix) { print $2; exit }' <<<"$IDENTITIES"
}

IDENTITY=""
if [[ -n "${MURMUR_SIGN_IDENTITY:-}" ]]; then
    if [[ "$MURMUR_SIGN_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] && \
       grep -Fq "$MURMUR_SIGN_IDENTITY" <<<"$IDENTITIES"; then
        IDENTITY="$MURMUR_SIGN_IDENTITY"
    else
        IDENTITY="$(pick_identity_hash "$MURMUR_SIGN_IDENTITY")"
    fi
    if [[ -z "$IDENTITY" ]]; then
        echo "error: no valid code-signing identity named \"$MURMUR_SIGN_IDENTITY\" is available in the keychain." >&2
        echo "Create or import a signing certificate with its private key, then verify it with:" >&2
        echo "  security find-identity -v -p codesigning" >&2
        echo "For a local self-signed certificate, use Keychain Access → Certificate Assistant → Create a Certificate with Key; name it \"$MURMUR_SIGN_IDENTITY\", choose Self-Signed Root and Code Signing, and confirm it appears under My Certificates with its private key." >&2
        if grep -qE '^[[:space:]]*[1-9][0-9]* valid identities found' <<<"$IDENTITIES"; then
            echo "Available identities:" >&2
            sed -nE 's/^[[:space:]]*[0-9]+\) //p' <<<"$IDENTITIES" >&2
        else
            echo "  (none found; security find-identity must list the certificate and its private key)" >&2
        fi
        exit 1
    fi
elif [[ -n "$(pick_identity_hash 'Developer ID Application: ')" ]]; then
    IDENTITY="$(pick_identity_hash 'Developer ID Application: ')"
elif [[ -n "$(pick_identity_hash 'Apple Development: ')" ]]; then
    IDENTITY="$(pick_identity_hash 'Apple Development: ')"
elif [[ -n "$(pick_identity_hash 'Murmur Dev')" ]]; then
    IDENTITY="$(pick_identity_hash 'Murmur Dev')"
fi

IDENTITY_NAME=""
if [[ -n "$IDENTITY" ]]; then
    IDENTITY_NAME="$(grep -F "$IDENTITY" <<<"$IDENTITIES" | sed -nE 's/.*"([^"]+)".*/\1/p')"
fi

echo "→ Building release..."
swift build -c release --product "$BIN_NAME" >/dev/null

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/$BIN_NAME"
[[ -x "$BIN_PATH" ]] || { echo "error: built binary not found at $BIN_PATH" >&2; exit 1; }

# Regenerate the procedural app icon if missing or stale relative to its
# sources. The generator compiles with MurmurDesign so it draws the same mark.
ICON_OUT="$ROOT/build/AppIcon.icns"
ICON_SRCS=("$ROOT/scripts/icon/main.swift" "$ROOT"/Sources/MurmurDesign/*.swift)
ICON_STALE=0
[[ -f "$ICON_OUT" ]] || ICON_STALE=1
for src in "${ICON_SRCS[@]}"; do
    if [[ "$src" -nt "$ICON_OUT" ]]; then ICON_STALE=1; fi
done
if [[ "$ICON_STALE" == 1 ]]; then
    echo "→ Generating AppIcon.icns..."
    mkdir -p "$ROOT/build"
    swiftc -O "${ICON_SRCS[@]}" -o "$ROOT/build/make_icon"
    "$ROOT/build/make_icon"
fi

echo "→ Assembling $BUNDLE (v$VERSION)..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/murmur"
if [[ -f "$ICON_OUT" ]]; then
    cp "$ICON_OUT" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Copy SwiftPM-generated resource bundles into Contents/Resources/. The
# install-location fix is in code: BundleModuleFallback.swift swizzles
# Bundle.init(path:) so the SwiftPM-generated Bundle.module accessor's
# first probe — `<App.app>/<name>.bundle`, which codesign forbids — gets
# transparently rewritten to `<App.app>/Contents/Resources/<name>.bundle`
# at runtime. That's where we drop them here, and it works for any
# install location, not just /Applications.
for bundle in "$BIN_DIR"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    cp -R "$bundle" "$BUNDLE/Contents/Resources/"
done

# Copy SwiftPM-resolved frameworks (e.g. Sparkle.framework, a
# .binaryTarget xcframework that lands in the release/ dir alongside the
# binary). They link against `@rpath/<Framework>.framework/...`; the
# binary's default rpath set by SwiftPM (`@loader_path`) finds them in
# the release/ dir but breaks once we move the binary into
# `Contents/MacOS/`. So: copy the framework AND patch the binary's rpath
# to look in `../Frameworks/`.
for fw in "$BIN_DIR"/*.framework; do
    [[ -d "$fw" ]] || continue
    mkdir -p "$BUNDLE/Contents/Frameworks"
    cp -R "$fw" "$BUNDLE/Contents/Frameworks/"
done
if [[ -d "$BUNDLE/Contents/Frameworks" ]]; then
    # `|| true` because install_name_tool errors out on repeat invocations
    # (re-adding an existing rpath). The bundle is rm -rf'd above so this
    # is the first add, but be defensive against future refactors.
    install_name_tool -add_rpath @executable_path/../Frameworks \
        "$BUNDLE/Contents/MacOS/murmur" 2>/dev/null || true
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>            <string>com.jackammon.murmur</string>
    <key>CFBundleName</key>                  <string>Murmur</string>
    <key>CFBundleDisplayName</key>           <string>Murmur</string>
    <key>CFBundleExecutable</key>            <string>murmur</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSMicrophoneUsageDescription</key>  <string>Murmur records your voice for on-device dictation and pastes the transcript at your cursor.</string>
    <key>NSHumanReadableCopyright</key>      <string>MIT — github.com/jackammon</string>
</dict>
</plist>
PLIST

ENTITLEMENTS="$ROOT/scripts/murmur.entitlements"

if [[ -n "$IDENTITY" ]]; then
    if [[ "$IDENTITY_NAME" == "Developer ID"* ]]; then
        # Distribution cert: hardened runtime + Apple TSA timestamp (required for notarization).
        echo "→ Signing for distribution: $IDENTITY_NAME ($IDENTITY)"
        codesign --force --deep --sign "$IDENTITY" \
            --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" \
            "$BUNDLE"
    else
        # Dev cert (Apple Development / self-signed): stable DR for TCC across
        # rebuilds; no hardened runtime needed (we're not notarizing).
        echo "→ Signing for dev iteration: $IDENTITY_NAME ($IDENTITY)"
        codesign --force --deep --sign "$IDENTITY" --timestamp=none \
            --entitlements "$ENTITLEMENTS" \
            "$BUNDLE"
    fi
    DR_LINE="$(codesign -dr - "$BUNDLE" 2>&1 | sed -n 's/^designated => //p')"
    [[ -n "$DR_LINE" ]] && echo "  DR: $DR_LINE"
else
    echo "→ Ad-hoc signing (TCC grants will reset on every rebuild — see header for stable signing options)..."
    codesign --sign - --force --deep --timestamp=none "$BUNDLE" 2>/dev/null || \
        echo "  (codesign skipped)"
fi

echo "✓ $BUNDLE"
echo "  Run with: open $BUNDLE"
