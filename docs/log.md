# Changelog

All notable changes to JPG Master (JPEGLI & JXL Converter) are documented here.

---

## Unreleased

### Added
- **PNG input support** — PNG files are now accepted as input for both JPEG and JXL export. PNG is read via Pillow into a numpy array and processed through the same pipeline as TIFF (temp PNG -> cjpegli/cjxl). Both 8-bit and 16-bit PNG are supported. Affects both Tkinter and PySide6 UIs: file dialogs, scan filters, labels, and format hints all updated.

### Changed
- Renamed internal `_read_tiff_array()` to `_read_image_array()` in both `converter_app.py` and `pyside6_app/core/conversion.py` to reflect support for TIFF and PNG.
- Updated error messages from "Failed to read TIFF" to "Failed to read image".
- Consolidated `plan.md`, `addplan1.md`, `multicore.md`, and `migrationplan.md` into `docs/development-plan.md`. Old files removed from root.
- Added `docs/architecture.md` documenting module structure, pipeline, method signatures, and key decisions.

---

## 2026-04-18

### Changed
- Renamed app to **JPG Master - JPEGLI & JXL Converter** across UI, PyInstaller spec, and README (`84fcd55`).
- Made Tkinter app window resizable (`b3ca8e2`).
- Removed `requirements.txt` and `multicore.md` from git tracking (kept as local files) (`1b327e0`).

### Added
- JXL and multi-core packaging support in build configuration (`41fbd6f`).

---

## 2026-04-17

### Added
- **Phase 7: macOS app packaging** — PyInstaller spec file (`converter_app.spec`) for bundling as a native `.app`. Bundles cjpegli, exiftool, and all required dylibs. Hidden imports for imagecodecs and tifffile. Bundle ID: `com.halebop17.jpegli-converter` (`f8773ba`).

---

## 2026-04-15

### Added
- **Phase 1: Initial release** — Tkinter batch converter GUI. TIFF input, JPEG output via cjpegli. Basic folder mode with file list and quality slider (`13cf38f`).
- **Conversion modes** — Single file, folder, and recursive tree modes. Mirror tree output structure option. Metadata strip toggle (`d1683a7`).
- **Image resize on export** — Four resize modes: long edge, short edge, percentage, width x height. Pillow LANCZOS resampling (`4c4c6c0`).
- **Phase 4: True 16-bit pipeline** — Replaced Pillow TIFF reading with tifffile for native uint16 preservation. Added imagecodecs for 16-bit PNG temp files. cjpegli now receives full 16-bit input when available (`f5beb1a`).

### Fixed
- **ICC profile preservation** — cjpegli strips ICC profiles during encoding. Added post-encode step: extract ICC via Pillow, embed via exiftool (`a828c8d`).
- **Resize mode inputs** — Fixed UI to show single value field for edge/percentage modes and two fields (W x H) for width-height mode (`80fda66`).
- **Percentage resize** — Allow upscaling (values > 100%) and default percentage to 100 instead of 50 (`9eda74f`).

### Changed
- Refined UI layout spacing and updated README (`5e8efa8`).
- Stopped tracking `TIFF Converter.app` bundle in git (`3db37ab`).
- Removed numpy from requirements.txt (already a transitive dependency) (`cf0ff85`).
