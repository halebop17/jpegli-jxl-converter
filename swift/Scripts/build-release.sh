#!/usr/bin/env bash
# build-release.sh — build a universal Release .app bundle.
# Output: swift/build/Release/JPG\ Master.app
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ ! -d "JPGMaster.xcodeproj" ]; then
    "$(dirname "$0")/generate-project.sh"
fi

if ! Vendor/build-deps.sh --check 2>/dev/null; then
    echo "Vendored libraries not built. Building now..."
    Vendor/build-deps.sh
fi

xcodebuild \
    -project JPGMaster.xcodeproj \
    -scheme JPGMaster \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

mkdir -p build/Release
cp -R build/DerivedData/Build/Products/Release/"JPG Master.app" build/Release/
echo "Built: $(pwd)/build/Release/JPG Master.app"
