# JPG Master — Swift / SwiftUI native app

Native macOS rewrite of the Python [converter_app.py](../converter_app.py).
The Python implementation remains the reference; this project is the
in-progress native port.

See [PLAN.md](PLAN.md) for the full development plan and verification
checklist.

## Architecture in one paragraph

In-process decode/encode of TIFF and PNG via vendored static libraries
(libtiff, libpng, lcms2, libexiv2 from pinned source releases).
Subprocess invocation of `cjpegli` and `cjxl`/`djxl` (the encoder CLI is
the only stable API surface, and isolation in a subprocess means an
encoder crash cannot bring down the app). SwiftUI UI, Swift concurrency
for the parallel conversion pool, vImage for high-quality resampling.

## Prerequisites

Install once (Homebrew):

```sh
brew install xcodegen cmake
```

Xcode 15+ is required (Swift 5.10, macOS 11+ deployment target).

## First-time setup

From the repo root:

```sh
cd swift

# 1. Build the vendored C/C++ dependencies. Slow first time
#    (compiles libtiff, libpng, lcms2, libexpat, libexiv2, zlib for
#    arm64 + x86_64 and combines them into universal static libs).
Vendor/build-deps.sh

# 2. Generate JPGMaster.xcodeproj from project.yml.
Scripts/generate-project.sh

# 3. Open in Xcode.
open JPGMaster.xcodeproj
```

You can now build and run from Xcode (⌘R).

The Python tool's existing encoder binaries in [bin/](../bin/) are
copied into the app bundle automatically by a build phase, and resolved
at runtime via `Bundle.main.resourceURL`.

## Building from the command line

```sh
Scripts/build-release.sh
```

Outputs `swift/build/Release/JPG Master.app` (universal arm64 + x86_64).

## Codesigning and notarization

For distribution outside your machine:

```sh
# 1. Sign with your Developer ID Application certificate.
Scripts/codesign-app.sh "build/Release/JPG Master.app" "Developer ID Application: Your Name (TEAMID)"

# 2. Notarize. Set credentials first:
export AC_USERNAME="you@example.com"
export AC_PASSWORD="app-specific-password"   # https://appleid.apple.com → app-specific passwords
export AC_TEAM_ID="ABC1234567"
Scripts/notarize.sh "build/Release/JPG Master.app"
```

## Updating vendored libraries

Versions and SHA-256 checksums are pinned in
[Vendor/versions.txt](Vendor/versions.txt). To upgrade a library:

1. Update the version string and URL.
2. Update the SHA-256 — verify against the upstream release announcement,
   not just by computing locally.
3. `rm -rf Vendor/build Vendor/src && Vendor/build-deps.sh`.
4. Rebuild and run the parity verification checklist in
   [PLAN.md](PLAN.md#verification-checklist-parity-tests).

Track upstream CVE feeds for libtiff, libpng, libexiv2, zlib, libexpat —
all are well-monitored projects.

## Layout

```
swift/
├── PLAN.md             ← development plan
├── README.md           ← this file
├── project.yml         ← XcodeGen project specification
├── JPGMaster/
│   ├── App/            ← @main, AppState
│   ├── Engine/         ← conversion pipeline (Swift)
│   ├── Bridge/         ← module.modulemap, ObjC++ libexiv2 wrapper, C shims
│   ├── UI/             ← SwiftUI views
│   └── Resources/      ← Info.plist, entitlements, AppIcon.icns
├── Vendor/
│   ├── build-deps.sh   ← fetches and builds vendored libs
│   ├── versions.txt    ← pinned versions + checksums
│   ├── src/            ← extracted sources (gitignored)
│   └── build/          ← output: include/, lib/ (gitignored)
└── Scripts/
    ├── generate-project.sh
    ├── build-release.sh
    ├── codesign-app.sh
    └── notarize.sh
```

## Status

Initial implementation. See [PLAN.md](PLAN.md) for the verification
checklist that must be satisfied before this can supersede the Python
app.
