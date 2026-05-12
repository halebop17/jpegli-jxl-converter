import Foundation
import CTiff

/// libtiff-backed TIFF reader. Preserves source bit depth (8 or 16),
/// normalises everything to RGB by stacking grayscale and alpha-compositing
/// RGBA over white, matching the Python pipeline's behaviour.
enum TIFFReader {

    static func read(_ url: URL) throws -> ImageBuffer {
        guard let tif = url.path.withCString({ TIFFOpen($0, "r") }) else {
            throw PipelineError.readFailed(url, "TIFFOpen returned null")
        }
        defer { TIFFClose(tif) }

        var width: UInt32 = 0
        var height: UInt32 = 0
        var samplesPerPixel: UInt16 = 0
        var bitsPerSample: UInt16 = 0
        var sampleFormat: UInt16 = UInt16(SAMPLEFORMAT_UINT)
        var photometric: UInt16 = 0
        var planarConfig: UInt16 = UInt16(PLANARCONFIG_CONTIG)
        var extraSamplesCount: UInt16 = 0
        var extraSamples: UnsafeMutablePointer<UInt16>? = nil

        TIFFGetField_uint32(tif, UInt32(TIFFTAG_IMAGEWIDTH), &width)
        TIFFGetField_uint32(tif, UInt32(TIFFTAG_IMAGELENGTH), &height)
        TIFFGetField_uint16(tif, UInt32(TIFFTAG_SAMPLESPERPIXEL), &samplesPerPixel)
        TIFFGetField_uint16(tif, UInt32(TIFFTAG_BITSPERSAMPLE), &bitsPerSample)
        TIFFGetField_uint16(tif, UInt32(TIFFTAG_SAMPLEFORMAT), &sampleFormat)
        TIFFGetField_uint16(tif, UInt32(TIFFTAG_PHOTOMETRIC), &photometric)
        TIFFGetField_uint16(tif, UInt32(TIFFTAG_PLANARCONFIG), &planarConfig)
        _ = TIFFGetField_extras(tif, UInt32(TIFFTAG_EXTRASAMPLES), &extraSamplesCount, &extraSamples)

        guard width > 0 && height > 0 else {
            throw PipelineError.readFailed(url, "image has zero dimension")
        }
        guard bitsPerSample == 8 || bitsPerSample == 16 else {
            throw PipelineError.readFailed(url, "unsupported bit depth: \(bitsPerSample)")
        }
        guard samplesPerPixel >= 1 && samplesPerPixel <= 4 else {
            throw PipelineError.readFailed(url, "unsupported samples per pixel: \(samplesPerPixel)")
        }

        // Strategy: use TIFFReadRGBAImageOriented for the safe fallback path
        // (handles all photometric interpretations, palettised, YCbCr, CMYK,
        // etc., normalising to 8-bit RGBA). For 16-bit RGB / RGBA, read raw
        // strips/tiles to preserve precision.
        let isHighPrecisionRGB = (bitsPerSample == 16)
            && (photometric == UInt16(PHOTOMETRIC_RGB) || photometric == UInt16(PHOTOMETRIC_MINISBLACK))
            && planarConfig == UInt16(PLANARCONFIG_CONTIG)

        if isHighPrecisionRGB {
            return try read16BitContig(tif: tif,
                                        url: url,
                                        width: Int(width),
                                        height: Int(height),
                                        spp: Int(samplesPerPixel),
                                        photometric: photometric,
                                        extraSamplesCount: Int(extraSamplesCount),
                                        extraSamples: extraSamples)
        } else {
            return try read8BitViaRGBA(tif: tif,
                                       url: url,
                                       width: Int(width),
                                       height: Int(height))
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 8-bit fallback via TIFFReadRGBAImageOriented (handles all formats)
    // Result is RGBA premultiplied-or-not depending on file; we composite
    // alpha over white explicitly to match the Python pipeline.
    // ─────────────────────────────────────────────────────────────────────

    private static func read8BitViaRGBA(tif: OpaquePointer,
                                        url: URL,
                                        width: Int,
                                        height: Int) throws -> ImageBuffer {
        let pixelCount = width * height
        let rgba = UnsafeMutablePointer<UInt32>.allocate(capacity: pixelCount)
        defer { rgba.deallocate() }

        let ok = TIFFReadRGBAImageOriented(tif,
                                            UInt32(width),
                                            UInt32(height),
                                            rgba,
                                            Int32(ORIENTATION_TOPLEFT),
                                            0)
        guard ok != 0 else {
            throw PipelineError.readFailed(url, "TIFFReadRGBAImage failed")
        }

        // Composite RGBA → RGB (over white) into a tight RGB buffer.
        var rgb = Data(count: pixelCount * 3)
        rgb.withUnsafeMutableBytes { (rawDest: UnsafeMutableRawBufferPointer) in
            guard let dest = rawDest.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<pixelCount {
                let p = rgba[i]
                let r = UInt8(truncatingIfNeeded:  p        & 0xFF)
                let g = UInt8(truncatingIfNeeded: (p >>  8) & 0xFF)
                let b = UInt8(truncatingIfNeeded: (p >> 16) & 0xFF)
                let a = UInt8(truncatingIfNeeded: (p >> 24) & 0xFF)
                if a == 255 {
                    dest[i*3 + 0] = r
                    dest[i*3 + 1] = g
                    dest[i*3 + 2] = b
                } else {
                    let af = Float(a) / 255.0
                    let inv = 1.0 - af
                    dest[i*3 + 0] = UInt8(min(255, max(0, Int(Float(r) * af + 255.0 * inv + 0.5))))
                    dest[i*3 + 1] = UInt8(min(255, max(0, Int(Float(g) * af + 255.0 * inv + 0.5))))
                    dest[i*3 + 2] = UInt8(min(255, max(0, Int(Float(b) * af + 255.0 * inv + 0.5))))
                }
            }
        }
        return ImageBuffer(width: width, height: height, bitDepth: .eight, pixels: rgb)
    }

    // ─────────────────────────────────────────────────────────────────────
    // 16-bit RGB / Gray (with optional alpha) — read scanlines or strips
    // to preserve precision, then alpha-composite over white at native depth.
    // ─────────────────────────────────────────────────────────────────────

    private static func read16BitContig(tif: OpaquePointer,
                                        url: URL,
                                        width: Int,
                                        height: Int,
                                        spp: Int,
                                        photometric: UInt16,
                                        extraSamplesCount: Int,
                                        extraSamples: UnsafeMutablePointer<UInt16>?) throws -> ImageBuffer {

        let isTiled = TIFFIsTiled(tif) != 0
        let scanlineBytes = Int(TIFFScanlineSize(tif))
        let samplesPerScanline = scanlineBytes / 2  // uint16 samples
        guard scanlineBytes > 0 else {
            throw PipelineError.readFailed(url, "TIFFScanlineSize returned 0")
        }

        // Read into a (width × height × spp) uint16 buffer, then collapse to
        // RGB16 with alpha composite if needed.
        let totalSamples = width * height * spp
        var raw = [UInt16](repeating: 0, count: totalSamples)

        try raw.withUnsafeMutableBufferPointer { (buf: inout UnsafeMutableBufferPointer<UInt16>) in
            guard let base = buf.baseAddress else { return }

            if isTiled {
                var tileWidth: UInt32 = 0
                var tileHeight: UInt32 = 0
                TIFFGetField_uint32(tif, UInt32(TIFFTAG_TILEWIDTH), &tileWidth)
                TIFFGetField_uint32(tif, UInt32(TIFFTAG_TILELENGTH), &tileHeight)
                let tileW = Int(tileWidth)
                let tileH = Int(tileHeight)
                guard tileW > 0 && tileH > 0 else {
                    throw PipelineError.readFailed(url, "invalid tile dimensions")
                }
                let tileSize = TIFFTileSize(tif)
                let tile = UnsafeMutablePointer<UInt16>.allocate(capacity: Int(tileSize) / 2)
                defer { tile.deallocate() }
                var y = 0
                while y < height {
                    var x = 0
                    while x < width {
                        let read = TIFFReadTile(tif, tile, UInt32(x), UInt32(y), 0, 0)
                        if read < 0 { throw PipelineError.readFailed(url, "TIFFReadTile failed") }
                        let copyW = min(tileW, width - x)
                        let copyH = min(tileH, height - y)
                        for ty in 0..<copyH {
                            let dstRow = base + ((y + ty) * width + x) * spp
                            let srcRow = tile + (ty * tileW * spp)
                            memcpy(dstRow, srcRow, copyW * spp * 2)
                        }
                        x += tileW
                    }
                    y += tileH
                }
            } else {
                let rowBuf = UnsafeMutablePointer<UInt16>.allocate(capacity: samplesPerScanline)
                defer { rowBuf.deallocate() }
                for row in 0..<height {
                    let read = TIFFReadScanline(tif, rowBuf, UInt32(row), 0)
                    if read < 0 { throw PipelineError.readFailed(url, "TIFFReadScanline failed") }
                    let dst = base + row * width * spp
                    memcpy(dst, rowBuf, width * spp * 2)
                }
            }
        }

        // Detect alpha channel (extra sample 1 = associated alpha, 2 = unassociated).
        let hasAlpha: Bool = {
            if photometric == UInt16(PHOTOMETRIC_RGB) && spp == 4 { return true }
            if photometric == UInt16(PHOTOMETRIC_MINISBLACK) && spp == 2 { return true }
            return extraSamplesCount > 0
        }()

        // Collapse to RGB16 with alpha composite over white.
        let pixelCount = width * height
        var rgb = Data(count: pixelCount * 3 * 2)
        rgb.withUnsafeMutableBytes { (rawDest: UnsafeMutableRawBufferPointer) in
            guard let dest = rawDest.bindMemory(to: UInt16.self).baseAddress else { return }

            switch photometric {
            case UInt16(PHOTOMETRIC_RGB):
                if spp == 3 {
                    // straight copy
                    for i in 0..<pixelCount {
                        dest[i*3 + 0] = raw[i*3 + 0]
                        dest[i*3 + 1] = raw[i*3 + 1]
                        dest[i*3 + 2] = raw[i*3 + 2]
                    }
                } else {
                    // RGBA → composite over white
                    for i in 0..<pixelCount {
                        let r = raw[i*spp + 0]
                        let g = raw[i*spp + 1]
                        let b = raw[i*spp + 2]
                        let a = raw[i*spp + 3]
                        if a == 65535 {
                            dest[i*3 + 0] = r
                            dest[i*3 + 1] = g
                            dest[i*3 + 2] = b
                        } else {
                            let af = Float(a) / 65535.0
                            let inv = 1.0 - af
                            dest[i*3 + 0] = UInt16(min(65535, max(0, Int(Float(r) * af + 65535.0 * inv + 0.5))))
                            dest[i*3 + 1] = UInt16(min(65535, max(0, Int(Float(g) * af + 65535.0 * inv + 0.5))))
                            dest[i*3 + 2] = UInt16(min(65535, max(0, Int(Float(b) * af + 65535.0 * inv + 0.5))))
                        }
                    }
                }
            case UInt16(PHOTOMETRIC_MINISBLACK):
                // grayscale → R=G=B
                for i in 0..<pixelCount {
                    let v = raw[i*spp + 0]
                    if hasAlpha && spp == 2 {
                        let a = raw[i*spp + 1]
                        let af = Float(a) / 65535.0
                        let inv = 1.0 - af
                        let composed = UInt16(min(65535, max(0, Int(Float(v) * af + 65535.0 * inv + 0.5))))
                        dest[i*3 + 0] = composed
                        dest[i*3 + 1] = composed
                        dest[i*3 + 2] = composed
                    } else {
                        dest[i*3 + 0] = v
                        dest[i*3 + 1] = v
                        dest[i*3 + 2] = v
                    }
                }
            default:
                // Caller (read()) only routes to this function when
                // photometric is RGB or MINISBLACK; this branch is
                // unreachable but required for exhaustiveness.
                preconditionFailure("unexpected photometric: \(photometric)")
            }
        }

        return ImageBuffer(width: width, height: height, bitDepth: .sixteen, pixels: rgb)
    }
}

// MARK: -
// Variadic-shim functions (TIFFGetField_uint32 etc.) are declared in
// shim_tiff.h and defined in shim_tiff_varargs.c, exported through the
// CTiff module.
