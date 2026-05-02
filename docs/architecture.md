# Architecture

JPG Master is a batch image converter with two UI frontends (Tkinter and PySide6) sharing the same conversion pipeline. It converts TIFF, PNG, and JPEG files to JPEG (via cjpegli) or JXL (via cjxl), and reconstructs JPEG from losslessly-transcoded JXL files (via djxl).

## Project structure

```
jpegli-converter/
├── converter_app.py              # Tkinter UI (legacy, self-contained)
├── converter_app.spec            # PyInstaller bundling config
├── check_tiff.py                 # Diagnostic tool
├── bin/                          # Bundled binaries (cjpegli, exiftool, dylibs)
├── pyside6_app/                  # PySide6 UI (modern, modular)
│   ├── main.py                   # Entry point
│   ├── core/
│   │   ├── binaries.py           # Binary detection
│   │   └── conversion.py         # Core conversion logic (no UI)
│   └── ui/
│       ├── main_window.py        # QMainWindow + page stack
│       ├── setup_page.py         # Settings + file selection
│       ├── conversion_page.py    # Progress display + worker thread
│       ├── file_table.py         # QAbstractTableModel for file lists
│       └── style.py              # QSS stylesheet + status colours
└── docs/
    ├── architecture.md           # This file
    └── log.md                    # Changelog
```

## Entry points

- Tkinter: `python3 converter_app.py`
- PySide6: `python3 -m pyside6_app.main`
- Diagnostic: `python3 check_tiff.py <file>`

## Module dependency graph

```
main.py
  -> main_window.py
       -> setup_page.py
       |    -> core/binaries.py
       |    -> core/conversion.py
       |    -> ui/file_table.py
       -> conversion_page.py
       |    -> core/conversion.py
       |    -> ui/file_table.py
       -> ui/style.py
```

`converter_app.py` is self-contained — it duplicates the core logic from `pyside6_app/core/conversion.py` inline.

---

## Conversion pipeline

### TIFF/PNG to JPEG

```
Source file (TIFF or PNG)
  -> _extract_icc()           Extract ICC profile via Pillow
  -> _read_image_array()      Read to numpy array (tifffile for TIFF, Pillow for PNG)
  -> _normalize_array()       Ensure (H, W, 3) RGB; alpha-composite RGBA onto white
  -> [resize]                 Optional resize via Pillow at 8-bit precision
  -> _write_png_temp()        Write temp PNG (imagecodecs for 16-bit, Pillow for 8-bit)
  -> cjpegli                  Encode temp PNG to JPEG at target quality
  -> exiftool                 Copy EXIF/IPTC/XMP + embed ICC from source
```

### TIFF/PNG to JXL

Same pipeline as above, but cjxl replaces cjpegli with `--effort` and `--container=1`.

### JPEG to JXL (lossless transcode)

```
Source JPEG -> cjxl --lossless_jpeg=1 --container=1 -> output JXL
```

Bitstream preserved exactly. No intermediate PNG, no re-encode.

### JXL to JPEG (reconstruction)

```
Source JXL -> djxl -> output JPEG (original reconstructed bit-for-bit)
```

### Dispatch logic

Both UIs use the same dispatch:

```python
if export_format == "jxl":
    convert_to_jxl(...)         # handles JPEG lossless transcode internally
elif src_ext in JXL_SUFFIXES:
    convert_jxl_to_jpeg(...)    # round-trip reconstruction
else:
    convert_tiff(...)           # TIFF and PNG path
```

---

## Key architectural decisions

### 16-bit pipeline preservation

TIFF files may be uint16. The pipeline preserves bit depth end-to-end:

- `tifffile.imread()` returns uint8 or uint16 natively
- `_normalize_array()` operates at the source dtype
- `_write_png_temp()` uses `imagecodecs.png_encode()` for uint16, Pillow for uint8
- cjpegli/cjxl receive 16-bit PNG input when available

Resize is the exception: Pillow only handles 8-bit RGB, so uint16 arrays are downscaled to uint8 for the resize operation, then restored to uint16. This is acceptable because resize is geometric only.

### Two UI frontends

`converter_app.py` (Tkinter) is the legacy app — self-contained in a single file. `pyside6_app/` is the modern rewrite with proper separation of concerns. Both share the same conversion pipeline logic (duplicated, not shared).

### Binary detection strategy

Binaries are located by checking paths in priority order:
1. Bundled in `bin/` (PyInstaller frozen app)
2. Homebrew Apple Silicon (`/opt/homebrew/bin/`)
3. Homebrew Intel (`/usr/local/bin/`)
4. System PATH via `shutil.which()`

### Metadata preservation

Metadata is transferred in two steps via exiftool:
1. Copy EXIF, IPTC, XMP tags from source to output
2. Embed ICC profile extracted from source via Pillow

When `strip_metadata=True`, both steps are skipped entirely.

---

## Constants

### File type suffixes

```python
TIFF_SUFFIXES = {".tif", ".tiff"}
JPEG_SUFFIXES = {".jpg", ".jpeg"}
JXL_SUFFIXES  = {".jxl"}
PNG_SUFFIXES  = {".png"}
```

### Resize modes

```python
RESIZE_MODES = [
    ("long_edge",  "Long Edge"),     # Limit longest dimension
    ("short_edge", "Short Edge"),    # Limit shortest dimension
    ("percentage", "Percentage"),    # Scale by percentage
    ("wh",         "Width & Height"),# Fit inside bounding box
]
```

### JXL effort levels

```python
effort_names = {
    1: "lightning", 2: "thunder", 3: "falcon", 4: "cheetah",
    5: "hare", 6: "wombat", 7: "squirrel", 8: "kitten", 9: "tortoise",
}
```

### Status colours (PySide6)

```python
STATUS_COLOURS = {
    "waiting":    ("#9e9e9e", "#ffffff"),    # grey
    "processing": ("#1565c0", "#bbdefb"),    # blue
    "converted":  ("#2e7d32", "#c8e6c9"),    # green
    "failed":     ("#c62828", "#ffcdd2"),    # red
    "cancelled":  ("#616161", "#eeeeee"),    # dark grey
}
```

---

## Method signatures by module

### pyside6_app/core/binaries.py

```python
def resource_root() -> Path
def find_cjpegli() -> str | None
def find_cjxl() -> str | None
def find_djxl() -> str | None
def find_exiftool() -> str | None
```

### pyside6_app/core/conversion.py

```python
# File scanning
def scan_files(
    root: Path, mode: str, export_format: str,
    single_file: Path | None = None,
) -> list[Path]

def compute_output_path(
    src: Path, mode: str, export_format: str,
    input_dir: Path | None, output_dir: Path | None,
    mirror_tree: bool,
) -> Path

# Resize
def apply_resize(
    img: Image.Image, mode: str, value: int,
    w: int = 3000, h: int = 2000,
) -> Image.Image

# Image I/O (internal)
def _extract_icc(src: Path) -> bytes | None
def _read_image_array(src: Path) -> tuple[np.ndarray, bool]
def _normalize_array(arr: np.ndarray) -> np.ndarray
def _write_png_temp(arr: np.ndarray, path: str) -> None
def _apply_resize_to_array(
    arr: np.ndarray, resize_mode: str, resize_value: int,
    resize_w: int, resize_h: int,
) -> np.ndarray

# Conversion
def convert_tiff(
    src: Path, dst: Path, quality: int, cjpegli: str,
    exiftool: str | None = None, strip_metadata: bool = False,
    resize_enabled: bool = False, resize_mode: str = "long_edge",
    resize_value: int = 3000, resize_w: int = 3000, resize_h: int = 2000,
) -> None

def convert_to_jxl(
    src: Path, dst: Path, quality: int, effort: int, cjxl: str,
    exiftool: str | None = None, strip_metadata: bool = False,
    resize_enabled: bool = False, resize_mode: str = "long_edge",
    resize_value: int = 3000, resize_w: int = 3000, resize_h: int = 2000,
) -> None

def convert_jxl_to_jpeg(src: Path, dst: Path, djxl: str) -> None
```

### pyside6_app/ui/main_window.py

```python
class MainWindow(QMainWindow):
    def __init__(self)
    def _on_convert(self, settings: dict)
    def _on_back(self)
```

### pyside6_app/ui/setup_page.py

```python
class SetupPage(QWidget):
    convert_requested = Signal(dict)

    def __init__(self, parent=None)
    def _mode_str(self) -> str
    def _format_str(self) -> str
    def get_files(self) -> list[Path]
    def get_file_model(self) -> FileTableModel
    def dragEnterEvent(self, event: QDragEnterEvent)
    def dropEvent(self, event: QDropEvent)
```

Settings dictionary emitted by `convert_requested`:

```python
{
    "files":          list[Path],
    "mode":           str,              # "file" | "folder" | "tree"
    "export_format":  str,              # "jpeg" | "jxl"
    "input_dir":      Path | None,
    "output_dir":     Path | None,
    "mirror_tree":    bool,
    "quality":        int,              # 1-100
    "effort":         int,              # 1-9 (JXL only)
    "strip_metadata": bool,
    "workers":        int,              # 1, 2, 4, 6
    "resize_enabled": bool,
    "resize_mode":    str,
    "resize_value":   int,
    "resize_w":       int,
    "resize_h":       int,
    "cjpegli":        str | None,
    "cjxl":           str | None,
    "djxl":           str | None,
    "exiftool":       str | None,
}
```

### pyside6_app/ui/conversion_page.py

```python
class ConversionWorker(QObject):
    row_updated  = Signal(Path, str, str)   # path, status, note
    progress     = Signal(int, int)          # done, total
    finished     = Signal(int, int, int)     # total, errors, cancelled
    elapsed_tick = Signal(str, str)          # elapsed_str, remaining_str

    def __init__(self, settings: dict, parent=None)
    def request_cancel(self)
    def run(self)

class ConversionPage(QWidget):
    back_requested = Signal()

    def __init__(self, parent=None)
    def start(self, settings: dict)
```

### pyside6_app/ui/file_table.py

```python
class FileTableModel(QAbstractTableModel):
    def __init__(self, parent=None, show_status: bool = False)
    def set_files(self, files: list[Path], root: Path | None = None)
    def reset_statuses(self)
    def set_status(self, path: Path, status: str, note: str = "") -> int | None
    def file_at(self, row: int) -> Path | None
    def file_count(self) -> int
```

### converter_app.py (legacy, self-contained)

```python
# Binary detection
def _resource_root() -> Path
def find_cjpegli() -> str | None
def find_cjxl() -> str | None
def find_djxl() -> str | None
def find_exiftool() -> str | None

# Image I/O
def _extract_icc(src: Path) -> bytes | None
def _read_image_array(src: Path) -> tuple[np.ndarray, bool]
def _normalize_array(arr: np.ndarray) -> np.ndarray
def _write_png_temp(arr: np.ndarray, path: str) -> None
def apply_resize(img: Image.Image, mode: str, value: int,
                 w: int = 3000, h: int = 2000) -> Image.Image

# Conversion
def convert_tiff(src, dst, quality, cjpegli, ...) -> None
def convert_to_jxl(src, dst, quality, effort, cjxl, ...) -> None
def convert_jxl_to_jpeg(src, dst, djxl) -> None

# UI
class ConverterApp(tk.Tk):
    def __init__(self)
    def _start_conversion(self)
    def _run_conversion(self)       # worker thread entry
    def _convert_one(self, src, fmt, quality, ...) -> None
    def _cancel_conversion(self) -> None
    def _back_to_settings(self) -> None
```

---

## Threading model

### Tkinter

- Main thread owns all widgets
- `_run_conversion()` runs in a daemon `threading.Thread`
- Within that thread, a `ThreadPoolExecutor(max_workers=N)` processes files in parallel
- UI updates marshalled via `self.after(0, callback)` (Tk thread-safe scheduling)
- Cancellation via `self._cancel_requested` flag checked before each file

### PySide6

- Main thread owns all widgets
- `ConversionWorker.run()` executes in a `QThread`
- Within that thread, a `ThreadPoolExecutor(max_workers=N)` processes files in parallel
- A daemon timer thread emits `elapsed_tick` every second for ETA display
- UI updates via Qt signals (thread-safe cross-thread communication)
- Cancellation via `self._cancel_flag` checked before each file
