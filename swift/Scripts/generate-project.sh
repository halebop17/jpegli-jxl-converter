#!/usr/bin/env bash
# generate-project.sh — regenerate JPGMaster.xcodeproj from project.yml.
# Run after editing project.yml or after a fresh clone.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not found. install with:  brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
echo "Generated JPGMaster.xcodeproj"
