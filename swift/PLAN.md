# Swift / macOS Native Port — Development Plan

Native Swift / SwiftUI rewrite of [converter_app.py](../converter_app.py). The
Python app stays as the reference implementation; this plan adds a `swift/`
project alongside it without disturbing the existing app.

## Goals

- **Bit-exact parity** with the Python pipeline. Same libraries underneath,
  called from Swift instead of through Python wrappers.
- **Maximum stability**. Reference C/C++ libraries vendored from pinned source
  releases. No reliance on system-provided imaging frameworks for steps where
  parity is load-bearing.
- **Clean process model**. The experimental encoders (`cjpegli`, `cjxl`,
  `djxl`) stay isolated in subprocesses. Decode/encode of well-defined
  formats happens in-process via vendored libraries.
- **Native macOS look and feel**. SwiftUI for the UI, GCD / Swift concurrency
  for parallelism.
- **Reproducible release builds**. Universal binary (arm64 + x86_64),
  hardened runtime, codesigned, notarized.

## Stack

| Concern | Choice | Why |
|---|---|---|
| TIFF read | vendored **libtiff** | Reference impl; matches `tifffile` parity |
| PNG read/write | vendored **libpng** + **zlib** | Explicit 16-bit control |
| Metadata (EXIF/IPTC/XMP/ICC) | vendored **libexiv2** (C++) | Replaces ExifTool (Perl), in-process, no external runtime |
| Color management | vendored **lcms2** | Reference ICC engine |
| JPEG encode | subprocess `cjpegli` (existing binary) | Stable CLI boundary |
| JXL encode/decode | subprocess `cjxl` / `djxl` | Same |
| Resize (Lanczos) | Apple **vImage** (Accelerate) | Fast, accurate, deterministic; not a parity-critical step |
| UI | **SwiftUI** | Native, reactive, modern |
| Concurrency | **TaskGroup** / `AsyncStream` | First-class Swift concurrency |
| Project generation | **XcodeGen** (project.yml) | Human-readable, version-control-friendly, deterministic |

## Repo layout (additive — nothing moved)

```
jpegli-converter/
├── converter_app.py         ← Python app, untouched
├── bin/                     ← shared: cjpegli, cjxl, dylibs (bundled into both apps)
├── icon/                    ← shared: app icon assets
├── packaging/               ← Python packaging, untouched
├── pyside6_app/             ← abandoned attempt, untouched
├── docs/
├── swift/                   ← NEW
│   ├── PLAN.md              ← this file
│   ├── README.md            ← build instructions
│   ├── project.yml          ← XcodeGen spec
│   ├── JPGMaster/           ← Swift / ObjC++ sources
│   │   ├── App/             ← @main, AppState, root view
│   │   ├── Engine/          ← conversion engine
│   │   ├── Bridge/          ← C and ObjC++ bridges (libtiff/libpng/lcms2/libexiv2)
│   │   ├── UI/              ← SwiftUI views
│   │   ├── Resources/       ← Assets.xcassets, Info.plist, entitlements
│   │   └── module.modulemap ← bridges vendored C libs to Swift
│   ├── Vendor/              ← vendored C/C++ libs (built from pinned tarballs)
│   │   ├── build-deps.sh    ← fetches, verifies, builds universal static libs
│   │   ├── versions.txt     ← pinned versions + sha256
│   │   ├── src/             ← extracted sources (gitignored)
│   │   └── build/           ← output: include/, lib/ (gitignored)
│   └── Scripts/             ← build / codesign / notarize helpers
└── README.md                ← updated to mention both implementations
```

## Build phases (Xcode)

1. **Pre-build run-script**: invoke `Vendor/build-deps.sh --check` — fails the
   build with a clear message if vendored libs aren't built yet. Manual one-time
   step, not auto-run, so the dev sees what's happening.
2. **Compile** Swift + ObjC++ sources, linking the static archives in
   `Vendor/build/lib`.
3. **Copy embedded binaries**: `bin/cjpegli`, `cjxl`, `djxl` and their dylibs
   into `Contents/Resources/bin/`. App resolves them at runtime via
   `Bundle.main.resourceURL`.
4. **Codesign embedded binaries** (each one separately, with
   `--options=runtime`).
5. **Codesign the app bundle**.
6. (Release only) **Notarize** via `notarytool`, then **staple**.

## Conversion pipeline (Swift, mirrors Python)

```
source file
  └─→ TIFFReader / PNGReader / [JPEG passthrough for JXL transcode]
        ├─→ ImageBuffer (uint8 or uint16, RGB, contiguous)
        │     └─→ MetadataTransfer.read(src) → captures EXIF/IPTC/XMP/ICC
        ├─→ ResizeOperation (optional, vImage Lanczos)
        ├─→ PNGWriter.writeTemp(buffer) → 8-bit or 16-bit intermediary
        └─→ SubprocessEncoder.run(cjpegli|cjxl, tmpPng, dst, args)
              └─→ MetadataTransfer.write(dst, captured) — unless strip-metadata
```

Special paths (parity with Python):

- `JPEG → JXL`: lossless transcode via `cjxl --lossless_jpeg=1 --container=1`.
  No intermediary PNG, no metadata transfer (preserved bit-exact by `cjxl`).
- `JXL → JPEG`: `djxl src dst` — round-trip reconstruction. No metadata
  transfer (JXL stores it inline).

## Phased implementation

### Phase 0 — repo prep
- Create `swift/` directory tree
- Add Xcode artifacts to `.gitignore`
- Stub `swift/README.md`

### Phase 1 — vendored deps
- `Vendor/versions.txt` — pinned tags + sha256
- `Vendor/build-deps.sh` — fetch, verify, build for arm64 + x86_64,
  produce universal `.a` files in `Vendor/build/lib`
- Test build manually; confirm static libs land where expected

### Phase 2 — Xcode project skeleton
- `project.yml` (XcodeGen) — single app target, Info.plist, entitlements,
  build phases for embedded binaries + codesign
- `module.modulemap` to expose C headers to Swift
- `Bridging-Header.h` for ObjC++ wrappers
- `Assets.xcassets` with app icon (sourced from `../icon/`)

### Phase 3 — Bridge layer
- `module.modulemap` exposes `tiff`, `png`, `lcms2` to Swift directly
- `ExivBridge.h/.mm` — Objective-C++ wrapper around libexiv2 (C++ API
  cannot bridge to Swift directly; ObjC++ is the standard pattern)
- Swift-side thin wrappers in `Bridge/` that trap C errors and convert to
  Swift `Error`

### Phase 4 — Core engine
- `ImageBuffer.swift` — pixel buffer (uint8 / uint16, RGB, planar layout)
- `TIFFReader.swift` — libtiff → ImageBuffer, preserves bit depth, handles
  strips and tiles, alpha-composite RGBA over white at native depth
- `PNGWriter.swift` — ImageBuffer → temp 8-bit or 16-bit PNG via libpng
- `ColorManager.swift` — lcms2 ICC reader (extract profile bytes from TIFF/PNG)
- `MetadataTransfer.swift` — libexiv2 wrapper: read EXIF/IPTC/XMP/ICC from
  source, write to dest
- `SubprocessEncoder.swift` — typed wrapper around `Process` for cjpegli /
  cjxl / djxl invocation, captures stdout/stderr, throws on non-zero exit
- `ResizeOperation.swift` — vImage Lanczos at uint16 precision when input is
  16-bit (vImage natively supports 16-bit channels — no precision loss)
- `ConversionJob.swift` — single-file pipeline (read → resize → write PNG →
  encode → metadata)
- `FileScanner.swift` — single-file / single-folder / recursive scan with
  format-aware filtering
- `WorkerPool.swift` — `TaskGroup` with N workers, cancellable, progress events

### Phase 5 — SwiftUI UI
- `JPGMasterApp.swift` — `@main`, window, app icon
- `AppState.swift` — `@Observable` model, mirrors Python `ConverterApp` state
- `ContentView.swift` — root layout (setup view ↔ conversion view)
- `SetupView.swift` — left column controls + right column file list
- Section views:
  - `ModeSection.swift` — single file / folder / recursive
  - `InputSection.swift` / `OutputSection.swift` — pickers
  - `FormatSection.swift` — JPEG / JXL with input-hint label
  - `QualitySection.swift` — slider with descriptive label
  - `EffortSection.swift` — JXL effort slider with cjxl preset names
  - `ResizeSection.swift` — mode picker + value inputs
  - `MetadataSection.swift` — strip checkbox + status indicator
  - `WorkersSection.swift` — 1/2/4/6 picker
  - `FolderStructureSection.swift` — mirror checkbox (recursive mode only)
- `FileListView.swift` — Treeview equivalent
- `ConversionView.swift` — per-file progress table, progress bar, cancel/back
- Color tags for status (waiting / processing / converted / failed / cancelled)

### Phase 6 — Packaging
- `Scripts/build-release.sh` — universal release build via `xcodebuild`
- `Scripts/codesign-app.sh` — sign embedded binaries + app
- `Scripts/notarize.sh` — submit, wait, staple

### Phase 7 — Docs
- `swift/README.md` with prerequisites, build steps, troubleshooting
- Update root `README.md` to mention both implementations
- Update `docs/log.md`

## Verification checklist (parity tests)

For each of these source types, confirm Swift output matches Python output
(visually and by file size within tolerance):

- [ ] 8-bit RGB TIFF → JPEG q85
- [ ] 16-bit RGB TIFF → JPEG q85 (the precision-critical path)
- [ ] 8-bit RGBA TIFF (alpha-composite over white) → JPEG q85
- [ ] PNG → JPEG q85
- [ ] 16-bit TIFF → JXL q90 effort 7
- [ ] JPEG → JXL lossless transcode (round-trip via djxl matches original byte-for-byte)
- [ ] JXL → JPEG (round-trip reconstruction)
- [ ] EXIF + IPTC + XMP + ICC preserved end-to-end
- [ ] `--strip-metadata` produces files with no EXIF/IPTC/XMP/ICC
- [ ] Resize: long edge / short edge / percentage / W×H — output dimensions match Pillow
- [ ] Recursive folder scan with mirror — output tree matches input tree
- [ ] Worker pool: 6 concurrent conversions, no race conditions, cancellation works
