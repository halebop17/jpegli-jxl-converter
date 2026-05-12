#!/usr/bin/env bash
# codesign-app.sh — sign the .app bundle and every embedded binary using
# the Developer ID identity. The app uses hardened runtime; embedded
# CLI tools are signed individually so notarization sees consistent
# signatures throughout the bundle.
#
# Usage:
#   codesign-app.sh <path/to/JPG\ Master.app> <Developer ID Application: ...>
set -euo pipefail

APP="${1:?usage: codesign-app.sh <app.bundle> <signing identity>}"
IDENTITY="${2:?usage: codesign-app.sh <app.bundle> <signing identity>}"

if [ ! -d "$APP" ]; then
    echo "error: app bundle not found: $APP" >&2
    exit 1
fi

ENTITLEMENTS="$(dirname "${BASH_SOURCE[0]}")/../JPGMaster/Resources/JPGMaster.entitlements"

echo "Signing embedded binaries…"
BIN_DIR="$APP/Contents/Resources/bin"
if [ -d "$BIN_DIR" ]; then
    for f in "$BIN_DIR"/*; do
        [ -f "$f" ] || continue
        codesign --force \
                 --options runtime \
                 --timestamp \
                 --sign "$IDENTITY" \
                 "$f"
    done
fi

echo "Signing main bundle…"
codesign --force \
         --deep \
         --options runtime \
         --timestamp \
         --entitlements "$ENTITLEMENTS" \
         --sign "$IDENTITY" \
         "$APP"

echo "Verifying…"
codesign --verify --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP" || true

echo "Signed: $APP"
