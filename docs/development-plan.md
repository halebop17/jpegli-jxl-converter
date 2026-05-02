# Development Plan

Complete development history and roadmap for JPG Master (JPEGLI & JXL Converter).

---

## Phase 1: TIFF to JPEGLI Batch Converter — COMPLETED

Initial Tkinter GUI for batch converting TIFF files to JPEG via cjpegli.

- Single folder mode with file list and quality slider
- Binary detection for cjpegli and exiftool
- Metadata preservation (EXIF, IPTC, XMP) via exiftool
- ICC profile extraction via Pillow, embedding via exiftool

---

## Phase 2: Conversion Modes and Metadata Toggle — COMPLETED

Extended the app to support real photo-library workflows.

### Conversion modes
- **Single File** — file picker, output next to source
- **Single Folder** — folder picker, configurable output directory
- **All Subfolders** — recursive scan via `rglob`, two output strategies:
  - Create `converted/` inside each source folder
  - Mirror full folder tree into a separate output root

### Output path resolver
- `file`: `src.parent / (src.stem + ext)`
- `folder`: `output_dir / (src.stem + ext)`
- `tree` + mirror disabled: `src.parent / "converted" / (src.stem + ext)`
- `tree` + mirror enabled: `output_dir / src.relative_to(input_root).parent / (src.stem + ext)`

### Metadata toggle
- `Strip all metadata` checkbox (default off)
- When checked: skip all exiftool calls and ICC embedding

### Validation rules
- Single File requires selected file
- Single Folder requires input + output folder
- All Subfolders requires input folder; mirror mode also requires output folder

---

## Phase 3: Image Resize on Export — COMPLETED

Optional image resizing during conversion, aspect ratio always preserved.

### Resize modes

| Mode | Description |
|---|---|
| Long Edge | Scale so longest side = N px |
| Short Edge | Scale so shortest side = N px |
| Percentage | Scale both dimensions by N% |
| Width & Height | Fit inside W x H bounding box (never crops) |

### Implementation
- `apply_resize(img, mode, value, w, h)` using Pillow LANCZOS resampling
- Images are never upscaled (except percentage mode allows > 100%)
- UI shows single value field for edge/percentage, two fields for W x H
- Default: 3000 px long edge / 3000 x 2000 W x H / 100%

---

## Phase 4: True 16-bit Pipeline — COMPLETED

Replaced Pillow TIFF reading with tifffile for native uint16 preservation.

### Problem
Pillow silently truncates 16-bit RGB TIFF data to uint8 on `.open()`. cjpegli supports 16-bit PNG input and processes at higher internal precision.

### Solution
```
tifffile.imread(src)          -> numpy uint16 (H, W, 3)   (lossless)
imagecodecs.png_encode(arr)   -> 16-bit PNG temp file      (lossless)
cjpegli tmp.png out.jpg       -> receives 16-bit pixels    (intended use)
```

### New dependencies
- `tifffile` — reads TIFF as numpy arrays preserving bit depth
- `imagecodecs` — writes 16-bit PNG from numpy uint16 arrays
- Pillow retained for ICC extraction, 8-bit PNG writing, and resize operations

### Helper functions introduced
- `_extract_icc(src)` — Pillow for ICC profile bytes only
- `_read_image_array(src)` — tifffile for TIFF, Pillow for PNG (returns array + is_16bit flag)
- `_normalize_array(arr)` — handles RGBA alpha compositing at native depth, grayscale to RGB
- `_write_png_temp(arr, path)` — imagecodecs for uint16, Pillow for uint8

### Backwards compatibility
- 8-bit TIFFs: tifffile returns uint8, same pipeline as before
- Resize: operates at 8-bit precision via Pillow, restored to uint16 after (acceptable for geometric operations)

---

## Multicore Conversion — COMPLETED

Concurrent file processing using a configurable thread pool.

### User options
- 1 (sequential), 2 (default), 4, 6 workers
- Selection disabled during active conversion

### Implementation
- `concurrent.futures.ThreadPoolExecutor(max_workers=N)`
- Shared counter protected by `threading.Lock`
- Tkinter: UI updates via `self.after(0, callback)`
- PySide6: UI updates via Qt signals (thread-safe cross-thread)
- Temp files use `tempfile.NamedTemporaryFile` (already thread-safe)
- Exiftool invocations are separate subprocesses on separate files (safe in parallel)

### Cancellation
- Sets flag checked before each new file
- Running workers finish their current file
- Remaining queued files marked as cancelled

---

## Conversion Status View and GUI Polish — COMPLETED

Second view shown after clicking Convert, replacing the setup screen.

### Status view
- `ttk.Treeview` (Tkinter) / `QTableView` (PySide6) with per-file status
- Columns: Filename, Status, Notes (error message if failed)
- Status row colours: waiting (grey), processing (blue), converted (green), failed (red), cancelled (grey)
- Overall progress bar with file counter
- Elapsed time and estimated remaining time
- Cancel button (disabled after all workers finish)
- Back to Settings button (disabled while running, keeps all settings on return)
- Error summary section listing each failed file with reason

### Two-frame architecture
- Setup frame and conversion frame in same window
- Tkinter: `grid_remove()` / `grid()` swap
- PySide6: `QStackedWidget` page switching

---

## Phase 5: JXL Export — COMPLETED

JPEG XL as an export format alongside JPEG.

### Supported input flows
- **TIFF/PNG to JXL** — same pipeline as JPEG (read array, normalize, temp PNG, cjxl)
- **JPEG to JXL** — lossless transcode via `cjxl --lossless_jpeg=1 --container=1` (bitstream preserved)
- **JXL to JPEG** — reconstruction via `djxl` (original JPEG recovered bit-for-bit)

### Binary detection
- `find_cjxl()` and `find_djxl()` added
- Search: `/opt/homebrew/bin/`, `/usr/local/bin/`, system PATH

### UI changes
- Export format selector: JPEG / JXL
- JXL effort slider (1-9, default 7 "squirrel")
- Quality default changes with format: 85 for JPEG, 90 for JXL
- Format hint text updates to show input/output types
- Effort control hidden when JPEG selected

### Metadata for JXL
- `--container=1` required for exiftool to write metadata to JXL
- Same EXIF/IPTC/XMP/ICC pipeline as JPEG output
- Strip metadata option works for JXL

### Dispatch logic
```python
if export_format == "jxl":
    convert_to_jxl(...)         # handles JPEG lossless transcode internally
elif src_ext in JXL_SUFFIXES:
    convert_jxl_to_jpeg(...)    # round-trip reconstruction
else:
    convert_tiff(...)           # TIFF and PNG path
```

---

## Phase 6: HEIC Export — DEFERRED

On hold until further notice.

### Planned scope
- HEIC as a third export format via `heif-enc` CLI or `pillow-heif`
- Reuse existing pipeline (resize, metadata, modes)
- Metadata handling uncertain — exiftool support for HEIC needs validation

### Open risks
- Encoder availability varies across machines
- Color profile behaviour needs testing with real TIFFs
- Licensing implications for distribution

---

## Phase 7: macOS App Packaging — COMPLETED

PyInstaller bundling as a native `.app` for direct download distribution.

### Bundle contents
- `cjpegli`, `exiftool` binaries
- `libjxl_threads.0.12.dylib`, `libjxl_cms.0.12.dylib`, `libjpeg.8.dylib`, `liblcms2.2.dylib`, `libhwy.1.dylib`
- Hidden imports for imagecodecs and tifffile via `collect_all()`

### Build configuration
- Bundle ID: `com.halebop17.jpegli-converter`
- App name: "JPG Master - JPEGLI & JXL Converter"
- Frozen resource root: `sys._MEIPASS`

### Signing and notarization
- Sign nested binaries first, then `.app`
- Hardened runtime enabled
- Notarize via `xcrun notarytool submit`, staple via `xcrun stapler staple`
- Distribute as `.dmg` (drag-and-drop install)

---

## PySide6 Migration — COMPLETED

Migrated UI from Tkinter to PySide6 for native macOS look and feel.

### Why PySide6
- Native macOS window chrome, dark/light mode, SF Pro fonts
- Native file dialogs (NSOpenPanel)
- Smooth scrolling, proper focus rings, hover states
- QSplitter resizable panels, drag-and-drop support
- Qt signals replace `self.after(0, ...)` for thread-safe UI updates
- PySide6 is LGPL v3 (safe for closed-source distribution)

### Architecture
```
pyside6_app/
├── main.py              # QApplication entry point
├── core/
│   ├── binaries.py      # Binary detection (extracted from converter_app.py)
│   └── conversion.py    # All conversion logic (no UI dependencies)
└── ui/
    ├── main_window.py   # QMainWindow + QStackedWidget
    ├── setup_page.py    # Settings + file list (QSplitter layout)
    ├── conversion_page.py # Progress + worker thread (ConversionWorker + signals)
    ├── file_table.py    # QAbstractTableModel shared by both pages
    └── style.py         # QSS stylesheet + status colours
```

### Key design decisions
- Tkinter app kept unchanged (`converter_app.py`) — both UIs coexist in same repo
- Core logic extracted to `pyside6_app/core/` as standalone functions
- `QStackedWidget` for page switching (setup / conversion)
- `QSplitter` for resizable left settings / right file list
- `ConversionWorker(QObject)` with signals: `row_updated`, `progress`, `finished`, `elapsed_tick`
- Worker runs `ThreadPoolExecutor` inside a `QThread`
- Daemon timer thread emits elapsed/ETA every second

### Trade-offs accepted
- Bundle size increased ~50-80 MB from Qt frameworks (trimmed by excluding unused modules)
- Cold start ~0.5-1.5s slower (acceptable for batch converter)
- All Qt `.framework` files require individual codesigning (scripted)

---

## PNG Input Support — COMPLETED

Added PNG as an accepted input format for both JPEG and JXL export.

### Implementation
- `PNG_SUFFIXES = {".png"}` added to constants
- `_read_image_array()` reads PNG via Pillow (8-bit), TIFF via tifffile (preserves 16-bit)
- PNG treated identically to TIFF in the pipeline: read to array, normalize, temp PNG, encode
- File dialogs, scan filters, and UI labels updated in both Tkinter and PySide6

---

## Future Ideas (not planned)

- HEIC export (Phase 6, deferred)
- Settings persistence via QSettings (recent folders, last-used format/quality)
- Quick presets (save/load quality + format combinations)
- Thumbnail preview of selected file
- Per-file timing in the Notes column
- Search/filter in the file table
- Menu bar (File > Open Folder, Help > About)
