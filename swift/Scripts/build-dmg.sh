#!/usr/bin/env bash
# build-dmg.sh — assemble a styled DMG for JPG Master via dmgbuild.
#
# Result:
#   - 540x380 window with the brand-cyan arrow background
#   - JPG Master.app on the left, Applications symlink on the right
#   - Volume icon set to the app's .icns
#   - .dmg file's Finder icon also set to the app's .icns
#   - Compressed UDZO, signed with Developer ID (timestamped)
#
# Window layout (background image alias + icon positions + volume
# icon) is produced by dmgbuild, which builds the .DS_Store directly
# rather than going through Finder + AppleScript (where the
# background alias race-condition with unmount silently drops the
# background on modern macOS).
#
# Usage:  build-dmg.sh <path/to/JPG Master.app> <output.dmg> [signing identity]
set -euo pipefail

APP="${1:?usage: build-dmg.sh <app.bundle> <output.dmg> [identity]}"
OUT_DMG="${2:?usage: build-dmg.sh <app.bundle> <output.dmg> [identity]}"
IDENTITY="${3:-Developer ID Application: Chananpat Atirojsakul (NHQ24QB25V)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ICNS="$REPO_ROOT/icon/app.icns"
BG_PNG="$SCRIPT_DIR/dmg-background.png"
SETTINGS="$SCRIPT_DIR/dmgbuild-settings.py"

[ -d "$APP" ]      || { echo "error: app not found: $APP" >&2; exit 1; }
[ -f "$ICNS" ]     || { echo "error: icns not found: $ICNS" >&2; exit 1; }
[ -f "$BG_PNG" ]   || { echo "error: background not found: $BG_PNG" >&2; exit 1; }
[ -f "$SETTINGS" ] || { echo "error: settings not found: $SETTINGS" >&2; exit 1; }
command -v dmgbuild >/dev/null || { echo "error: dmgbuild not installed (pip3 install dmgbuild)" >&2; exit 1; }

WORK="$(mktemp -d /tmp/jpgmaster-dmg.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

rm -f "$OUT_DMG"

echo "Building DMG with dmgbuild…"
dmgbuild -s "$SETTINGS" \
    -D app="$APP" \
    -D icon="$ICNS" \
    -D background="$BG_PNG" \
    "JPG Master" "$OUT_DMG"

echo "Setting Finder icon on the .dmg file…"
SIDE="$WORK/icon-sidecar"
cp "$ICNS" "$SIDE"
sips -i "$SIDE" >/dev/null
DeRez -only icns "$SIDE" > "$WORK/icon.rsrc"
Rez -append "$WORK/icon.rsrc" -o "$OUT_DMG"
SetFile -a C "$OUT_DMG"

echo "Signing…"
codesign --force --sign "$IDENTITY" --timestamp "$OUT_DMG"
codesign --verify --verbose=2 "$OUT_DMG"

echo "Done: $OUT_DMG"
