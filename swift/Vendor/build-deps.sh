#!/usr/bin/env bash
# build-deps.sh — fetch, verify and build vendored C/C++ dependencies as
# universal (arm64 + x86_64) static libraries.
#
# Outputs: swift/Vendor/build/{include,lib}
# Inputs:  swift/Vendor/versions.txt (pinned versions + sha256)
#
# Run once after cloning the repo. Re-run when versions.txt changes.

set -euo pipefail

VENDOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADS="$VENDOR_DIR/downloads"
SRC_DIR="$VENDOR_DIR/src"
BUILD_DIR="$VENDOR_DIR/build"
INSTALL_PREFIX="$BUILD_DIR"
LOG_DIR="$VENDOR_DIR/build-logs"

# Several dependency makefiles (zlib, libpng, lcms2, libexpat) do not
# correctly quote their install prefix, so a path containing whitespace
# (very common on macOS — "git repos", "My Drive", etc.) breaks `make
# install`. We work around this by performing all per-package builds
# inside a scratch directory whose path is guaranteed to contain no
# spaces, then copying the artifacts into INSTALL_PREFIX afterwards.
WORK_ROOT="${TMPDIR:-/tmp}"
WORK_ROOT="${WORK_ROOT%/}"
WORK_PREFIX="$WORK_ROOT/jpgmaster-vendor-build"

MIN_MACOS="13.0"
ARCHS=(arm64 x86_64)

mkdir -p "$DOWNLOADS" "$SRC_DIR" "$BUILD_DIR" "$LOG_DIR" "$WORK_PREFIX"

# ──────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────

log()    { printf '\033[1;34m[deps]\033[0m %s\n' "$*" >&2; }
warn()   { printf '\033[1;33m[deps]\033[0m %s\n' "$*" >&2; }
err()    { printf '\033[1;31m[deps]\033[0m %s\n' "$*" >&2; }
die()    { err "$*"; exit 1; }

ncpu() { sysctl -n hw.ncpu 2>/dev/null || echo 4; }

host_triplet_for() {
    # Some bundled config.sub files (notably lcms2's) predate arm64
    # naming and only know aarch64-apple-darwin. Map accordingly.
    case "$1" in
        arm64)  echo "aarch64-apple-darwin" ;;
        x86_64) echo "x86_64-apple-darwin"  ;;
        *)      echo "$1-apple-darwin"      ;;
    esac
}

verify_sha() {
    local file="$1" expected="$2"
    local actual
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        die "checksum mismatch for $file
  expected: $expected
  actual:   $actual"
    fi
}

fetch_and_extract() {
    local name="$1" version="$2" url="$3" sha="$4"
    local archive
    archive="$DOWNLOADS/$(basename "$url")"

    if [[ ! -f "$archive" ]]; then
        log "fetching $name $version"
        curl --fail --silent --show-error --location --output "$archive" "$url"
    fi
    verify_sha "$archive" "$sha"

    local extract_marker="$SRC_DIR/.${name}-${version}.extracted"
    if [[ -f "$extract_marker" ]]; then
        return 0
    fi

    log "extracting $name $version"
    rm -rf "$SRC_DIR/$name"
    mkdir -p "$SRC_DIR/$name"
    case "$archive" in
        *.tar.gz|*.tgz) tar -xzf "$archive" -C "$SRC_DIR/$name" --strip-components=1 ;;
        *.tar.xz)       tar -xJf "$archive" -C "$SRC_DIR/$name" --strip-components=1 ;;
        *.tar.bz2)      tar -xjf "$archive" -C "$SRC_DIR/$name" --strip-components=1 ;;
        *)              die "unknown archive format: $archive" ;;
    esac
    touch "$extract_marker"
}

# Read a single record from versions.txt by name. Sets globals VER, URL, SHA.
read_version() {
    local target="$1" line name ver url sha
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "${line// }" ]] && continue
        # shellcheck disable=SC2086
        read -r name ver url sha <<< "$line"
        if [[ "$name" == "$target" ]]; then
            VER="$ver"; URL="$url"; SHA="$sha"
            return 0
        fi
    done < "$VENDOR_DIR/versions.txt"
    die "version entry for '$target' not found in versions.txt"
}

# Combine arch-specific static libs into a single universal .a using lipo.
lipo_combine() {
    local libname="$1"
    local out="$INSTALL_PREFIX/lib/$libname"
    local inputs=()
    for arch in "${ARCHS[@]}"; do
        local candidate="$INSTALL_PREFIX/lib-$arch/$libname"
        [[ -f "$candidate" ]] || die "missing per-arch lib: $candidate"
        inputs+=("$candidate")
    done
    mkdir -p "$INSTALL_PREFIX/lib"
    if [[ ${#inputs[@]} -eq 1 ]]; then
        cp "${inputs[0]}" "$out"
    else
        lipo -create "${inputs[@]}" -output "$out"
    fi
    log "  → $out ($(lipo -archs "$out"))"
}

# ──────────────────────────────────────────────────────────────────────────
# Per-library build functions
# Each function builds for one arch into $INSTALL_PREFIX/lib-$arch
# ──────────────────────────────────────────────────────────────────────────

build_zlib() {
    local arch="$1" prefix="$WORK_PREFIX/zlib-$arch"
    local srcdir="$WORK_PREFIX/zlib-src-$arch"
    rm -rf "$srcdir" "$prefix"
    cp -R "$SRC_DIR/zlib" "$srcdir"
    mkdir -p "$prefix"
    log "building zlib for $arch"
    (
        cd "$srcdir"
        make distclean >/dev/null 2>&1 || true
        CFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -fPIC" \
        LDFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS" \
        ./configure --prefix="$prefix" --static
        make -j"$(ncpu)"
        make install
    ) > "$LOG_DIR/zlib-$arch.log" 2>&1
    mkdir -p "$INSTALL_PREFIX/lib-$arch" "$INSTALL_PREFIX/include"
    cp "$prefix/lib/libz.a" "$INSTALL_PREFIX/lib-$arch/"
    cp -R "$prefix/include/." "$INSTALL_PREFIX/include/"
}

build_libpng() {
    local arch="$1" prefix="$WORK_PREFIX/libpng-$arch"
    local srcdir="$WORK_PREFIX/libpng-src-$arch"
    local zlib_prefix="$WORK_PREFIX/zlib-$arch"
    rm -rf "$srcdir" "$prefix"
    cp -R "$SRC_DIR/libpng" "$srcdir"
    mkdir -p "$prefix"
    log "building libpng for $arch"
    (
        cd "$srcdir"
        make distclean >/dev/null 2>&1 || true
        CFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -fPIC -I$zlib_prefix/include" \
        LDFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -L$zlib_prefix/lib" \
        CPPFLAGS="-I$zlib_prefix/include" \
        ./configure \
            --prefix="$prefix" \
            --host="$(host_triplet_for "$arch")" \
            --disable-shared --enable-static \
            --disable-tools
        make -j"$(ncpu)"
        make install
    ) > "$LOG_DIR/libpng-$arch.log" 2>&1
    mkdir -p "$INSTALL_PREFIX/lib-$arch" "$INSTALL_PREFIX/include"
    cp "$prefix/lib/libpng16.a" "$INSTALL_PREFIX/lib-$arch/"
    cp -R "$prefix/include/." "$INSTALL_PREFIX/include/"
}

build_libtiff() {
    local arch="$1" prefix="$WORK_PREFIX/libtiff-$arch"
    local srcdir="$WORK_PREFIX/libtiff-src-$arch"
    local builddir="$WORK_PREFIX/libtiff-build-$arch"
    local zlib_prefix="$WORK_PREFIX/zlib-$arch"
    rm -rf "$srcdir" "$builddir" "$prefix"
    cp -R "$SRC_DIR/libtiff" "$srcdir"
    mkdir -p "$prefix" "$builddir"
    log "building libtiff for $arch"
    (
        cd "$builddir"
        cmake "$srcdir" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_ARCHITECTURES="$arch" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
            -DCMAKE_INSTALL_PREFIX="$prefix" \
            -DCMAKE_PREFIX_PATH="$zlib_prefix" \
            -DCMAKE_C_FLAGS="-fPIC" \
            -DBUILD_SHARED_LIBS=OFF \
            -Dtiff-tools=OFF \
            -Dtiff-tests=OFF \
            -Dtiff-contrib=OFF \
            -Dtiff-docs=OFF \
            -Djpeg=OFF \
            -Dold-jpeg=OFF \
            -Djbig=OFF \
            -Dlerc=OFF \
            -Dlzma=OFF \
            -Dzstd=OFF \
            -Dwebp=OFF \
            -Dlibdeflate=OFF \
            -Dzlib=ON \
            -DZLIB_ROOT="$zlib_prefix"
        cmake --build . --config Release -j"$(ncpu)"
        cmake --install .
    ) > "$LOG_DIR/libtiff-$arch.log" 2>&1
    mkdir -p "$INSTALL_PREFIX/lib-$arch" "$INSTALL_PREFIX/include"
    cp "$prefix/lib/libtiff.a"   "$INSTALL_PREFIX/lib-$arch/"
    cp "$prefix/lib/libtiffxx.a" "$INSTALL_PREFIX/lib-$arch/" 2>/dev/null || true
    cp -R "$prefix/include/." "$INSTALL_PREFIX/include/"
}

build_lcms2() {
    local arch="$1" prefix="$WORK_PREFIX/lcms2-$arch"
    local srcdir="$WORK_PREFIX/lcms2-src-$arch"
    rm -rf "$srcdir" "$prefix"
    cp -R "$SRC_DIR/lcms2" "$srcdir"
    mkdir -p "$prefix"
    log "building lcms2 for $arch"
    (
        cd "$srcdir"
        make distclean >/dev/null 2>&1 || true
        CFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -fPIC" \
        LDFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS" \
        ./configure \
            --prefix="$prefix" \
            --host="$(host_triplet_for "$arch")" \
            --disable-shared --enable-static
        make -j"$(ncpu)"
        make install
    ) > "$LOG_DIR/lcms2-$arch.log" 2>&1
    mkdir -p "$INSTALL_PREFIX/lib-$arch" "$INSTALL_PREFIX/include"
    cp "$prefix/lib/liblcms2.a" "$INSTALL_PREFIX/lib-$arch/"
    cp -R "$prefix/include/." "$INSTALL_PREFIX/include/"
}

build_libexpat() {
    local arch="$1" prefix="$WORK_PREFIX/libexpat-$arch"
    local srcdir="$WORK_PREFIX/libexpat-src-$arch"
    rm -rf "$srcdir" "$prefix"
    cp -R "$SRC_DIR/libexpat" "$srcdir"
    mkdir -p "$prefix"
    log "building libexpat for $arch"
    (
        cd "$srcdir"
        make distclean >/dev/null 2>&1 || true
        CFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS -fPIC" \
        LDFLAGS="-arch $arch -mmacosx-version-min=$MIN_MACOS" \
        ./configure \
            --prefix="$prefix" \
            --host="$(host_triplet_for "$arch")" \
            --disable-shared --enable-static \
            --without-docbook --without-examples --without-tests
        make -j"$(ncpu)"
        make install
    ) > "$LOG_DIR/libexpat-$arch.log" 2>&1
    mkdir -p "$INSTALL_PREFIX/lib-$arch" "$INSTALL_PREFIX/include"
    cp "$prefix/lib/libexpat.a" "$INSTALL_PREFIX/lib-$arch/"
    cp -R "$prefix/include/." "$INSTALL_PREFIX/include/"
}

build_inih() {
    local arch="$1" prefix="$WORK_PREFIX/inih-$arch"
    local srcdir="$WORK_PREFIX/inih-src-$arch"
    rm -rf "$srcdir" "$prefix"
    cp -R "$SRC_DIR/inih" "$srcdir"
    mkdir -p "$prefix/include" "$prefix/lib"
    log "building inih for $arch"
    (
        cd "$srcdir"
        cc -arch "$arch" -mmacosx-version-min="$MIN_MACOS" -fPIC -O2 \
            -DINI_USE_STACK=1 -DINI_ALLOW_MULTILINE=1 \
            -c ini.c -o ini.o
        ar rcs "$prefix/lib/libinih.a" ini.o
        c++ -arch "$arch" -mmacosx-version-min="$MIN_MACOS" -fPIC -O2 \
            -std=c++17 -I. \
            -c cpp/INIReader.cpp -o INIReader.o
        ar rcs "$prefix/lib/libINIReader.a" INIReader.o
        # Headers live directly in include/ so exiv2's Findinih.cmake
        # `find_path(NAMES ini.h)` resolves on the first try.
        cp ini.h            "$prefix/include/ini.h"
        cp cpp/INIReader.h  "$prefix/include/INIReader.h"
    ) > "$LOG_DIR/inih-$arch.log" 2>&1
    mkdir -p "$INSTALL_PREFIX/lib-$arch"
    cp "$prefix/lib/libinih.a"     "$INSTALL_PREFIX/lib-$arch/"
    cp "$prefix/lib/libINIReader.a" "$INSTALL_PREFIX/lib-$arch/"
    cp "$prefix/include/ini.h"      "$INSTALL_PREFIX/include/"
    cp "$prefix/include/INIReader.h" "$INSTALL_PREFIX/include/"
}

build_libexiv2() {
    local arch="$1" prefix="$WORK_PREFIX/libexiv2-$arch"
    local srcdir="$WORK_PREFIX/libexiv2-src-$arch"
    local builddir="$WORK_PREFIX/libexiv2-build-$arch"
    local expat_prefix="$WORK_PREFIX/libexpat-$arch"
    local zlib_prefix="$WORK_PREFIX/zlib-$arch"
    local inih_prefix="$WORK_PREFIX/inih-$arch"
    rm -rf "$srcdir" "$builddir" "$prefix"
    cp -R "$SRC_DIR/libexiv2" "$srcdir"
    mkdir -p "$prefix" "$builddir"
    log "building libexiv2 for $arch"
    (
        cd "$builddir"
        cmake "$srcdir" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_ARCHITECTURES="$arch" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
            -DCMAKE_INSTALL_PREFIX="$prefix" \
            -DCMAKE_PREFIX_PATH="$expat_prefix;$zlib_prefix;$inih_prefix" \
            -DCMAKE_CXX_FLAGS="-fPIC" \
            -DCMAKE_C_FLAGS="-fPIC" \
            -DBUILD_SHARED_LIBS=OFF \
            -DEXIV2_ENABLE_XMP=ON \
            -DEXIV2_ENABLE_EXTERNAL_XMP=OFF \
            -DEXIV2_ENABLE_PNG=ON \
            -DEXIV2_ENABLE_NLS=OFF \
            -DEXIV2_ENABLE_PRINTUCS2=ON \
            -DEXIV2_ENABLE_LENSDATA=OFF \
            -DEXIV2_ENABLE_VIDEO=OFF \
            -DEXIV2_ENABLE_WEBREADY=OFF \
            -DEXIV2_ENABLE_CURL=OFF \
            -DEXIV2_ENABLE_BMFF=OFF \
            -DEXIV2_ENABLE_BROTLI=OFF \
            -DEXIV2_BUILD_SAMPLES=OFF \
            -DEXIV2_BUILD_EXIV2_COMMAND=OFF \
            -DEXIV2_BUILD_UNIT_TESTS=OFF \
            -DEXIV2_BUILD_DOC=OFF
        cmake --build . --config Release -j"$(ncpu)"
        cmake --install .
    ) > "$LOG_DIR/libexiv2-$arch.log" 2>&1
    mkdir -p "$INSTALL_PREFIX/lib-$arch" "$INSTALL_PREFIX/include"
    cp "$prefix/lib/libexiv2.a"        "$INSTALL_PREFIX/lib-$arch/"
    cp "$prefix/lib/libexiv2-xmp.a"    "$INSTALL_PREFIX/lib-$arch/" 2>/dev/null || true
    cp -R "$prefix/include/." "$INSTALL_PREFIX/include/"
}

# ──────────────────────────────────────────────────────────────────────────
# Orchestration
# ──────────────────────────────────────────────────────────────────────────

build_lib() {
    local name="$1" build_fn="$2"
    read_version "$name"
    fetch_and_extract "$name" "$VER" "$URL" "$SHA"
    for arch in "${ARCHS[@]}"; do
        $build_fn "$arch"
    done
}

main() {
    if [[ "${1:-}" == "--check" ]]; then
        local missing=()
        for lib in libtiff libpng lcms2 libexiv2 libexpat libinih libINIReader libz; do
            local primary
            case "$lib" in
                libpng)     primary="libpng16.a" ;;
                lcms2)      primary="liblcms2.a" ;;
                *)          primary="${lib}.a" ;;
            esac
            [[ -f "$INSTALL_PREFIX/lib/$primary" ]] || missing+=("$lib")
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            err "vendored libraries not built: ${missing[*]}"
            err "run:  swift/Vendor/build-deps.sh"
            exit 1
        fi
        log "vendored libraries OK"
        exit 0
    fi

    log "checking host tools"
    for tool in curl tar shasum lipo cmake make; do
        command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
    done

    log "build prefix: $INSTALL_PREFIX"
    log "archs:        ${ARCHS[*]}"
    log "min macOS:    $MIN_MACOS"

    # Order matters: libpng → zlib; libtiff → zlib; libexiv2 → libexpat.
    build_lib zlib     build_zlib
    build_lib libpng   build_libpng
    build_lib libtiff  build_libtiff
    build_lib lcms2    build_lcms2
    build_lib libexpat build_libexpat
    build_lib inih     build_inih
    build_lib libexiv2 build_libexiv2

    log "combining per-arch libs into universal binaries"
    lipo_combine libz.a
    lipo_combine libpng16.a
    lipo_combine libtiff.a
    [[ -f "$INSTALL_PREFIX/lib-arm64/libtiffxx.a" ]] && lipo_combine libtiffxx.a
    lipo_combine liblcms2.a
    lipo_combine libexpat.a
    lipo_combine libinih.a
    lipo_combine libINIReader.a
    lipo_combine libexiv2.a
    [[ -f "$INSTALL_PREFIX/lib-arm64/libexiv2-xmp.a" ]] && lipo_combine libexiv2-xmp.a

    log "done. universal static libs in $INSTALL_PREFIX/lib"
}

main "$@"
