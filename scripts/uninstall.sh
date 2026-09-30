#!/usr/bin/env bash
set -euo pipefail

REMOVE_ALL_DATA=0
SKIP_CONFIRMATION=0

for argument in "$@"; do
    case "$argument" in
        --all-data) REMOVE_ALL_DATA=1 ;;
        --yes) SKIP_CONFIRMATION=1 ;;
        *) echo "usage: bash scripts/uninstall.sh [--all-data] [--yes]" >&2; exit 1 ;;
    esac
done

if (( REMOVE_ALL_DATA == 1 && SKIP_CONFIRMATION == 0 )); then
    read -r -p "Delete Murmur's downloaded models, history, settings, and permission grants? [y/N] " RESPONSE
    [[ "$RESPONSE" == "y" || "$RESPONSE" == "Y" ]] || exit 0
fi

/usr/bin/pkill -x murmur 2>/dev/null || true

USER_APP="$HOME/Applications/Murmur.app"
if [[ -d "$USER_APP" ]]; then
    rm -rf "$USER_APP"
    echo "Removed $USER_APP"
fi

SYSTEM_APP="/Applications/Murmur.app"
if [[ -d "$SYSTEM_APP" ]]; then
    echo "Murmur also exists at $SYSTEM_APP. Remove that copy in Finder or rerun this script with permission to write to /Applications." >&2
fi

if (( REMOVE_ALL_DATA == 1 )); then
    APPLICATION_SUPPORT="$HOME/Library/Application Support/Murmur"
    CACHE_DIRECTORY="$HOME/Library/Caches/com.jackammon.murmur"
    HTTP_STORAGE="$HOME/Library/HTTPStorages/com.jackammon.murmur"
    SAVED_STATE="$HOME/Library/Saved Application State/com.jackammon.murmur.savedState"
    PREFERENCES="$HOME/Library/Preferences/com.jackammon.murmur.plist"

    for path in "$APPLICATION_SUPPORT" "$CACHE_DIRECTORY" "$HTTP_STORAGE" "$SAVED_STATE" "$PREFERENCES"; do
        if [[ -e "$path" ]]; then
            rm -rf "$path"
        fi
    done
    defaults delete com.jackammon.murmur >/dev/null 2>&1 || true
    tccutil reset Microphone com.jackammon.murmur >/dev/null 2>&1 || true
    tccutil reset Accessibility com.jackammon.murmur >/dev/null 2>&1 || true
    tccutil reset PostEvent com.jackammon.murmur >/dev/null 2>&1 || true
    echo "Removed Murmur's models, history, settings, caches, and TCC permission grants."
fi
