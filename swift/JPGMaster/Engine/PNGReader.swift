import Foundation
import CPng

/// libpng-backed PNG reader. Preserves source bit depth (8 or 16) and
/// normalises to RGB by alpha-compositing RGBA over white. Matches the
/// Python pipeline's behaviour.
enum PNGReader {

    static func read(_ url: URL) throws -> ImageBuffer {
        guard let fp = fopen(url.path, "rb") else {
            throw PipelineError.readFailed(url, "fopen failed")
        }
        defer { fclose(fp) }

        guard let png = png_create_read_struct(PNG_LIBPNG_VER_STRING, nil, nil, nil) else {
            throw PipelineError.readFailed(url, "png_create_read_struct failed")
        }
        guard let info = png_create_info_struct(png) else {
            var p: png_structp? = png
            png_destroy_read_struct(&p, nil, nil)
            throw PipelineError.readFailed(url, "png_create_info_struct failed")
        }
        defer {
            var p: png_structp? = png
            var i: png_infop? = info
            png_destroy_read_struct(&p, &i, nil)
        }

        png_init_io(png, fp)

        var width: png_uint_32 = 0
        var height: png_uint_32 = 0
        var bitDepth: Int32 = 0
        var colorType: Int32 = 0

        png_read_info(png, info)
        width = png_get_image_width(png, info)
        height = png_get_image_height(png, info)
        bitDepth = Int32(png_get_bit_depth(png, info))
        colorType = Int32(png_get_color_type(png, info))

        // Expand palette to RGB; expand 1/2/4-bit gray to 8-bit.
        if colorType == PNG_COLOR_TYPE_PALETTE { png_set_palette_to_rgb(png) }
        if colorType == PNG_COLOR_TYPE_GRAY && bitDepth < 8 {
            png_set_expand_gray_1_2_4_to_8(png)
        }
        if png_get_valid(png, info, png_uint_32(PNG_INFO_tRNS)) != 0 {
            png_set_tRNS_to_alpha(png)
        }
        // Convert grayscale to RGB.
        if colorType == PNG_COLOR_TYPE_GRAY || colorType == PNG_COLOR_TYPE_GRAY_ALPHA {
            png_set_gray_to_rgb(png)
        }
        // libpng stores 16-bit channels in network byte order. We want host
        // (little-endian on Apple Silicon and Intel macOS) — swap on read.
        if bitDepth == 16 {
            png_set_swap(png)
        }

        png_read_update_info(png, info)
        let updatedColorType = Int32(png_get_color_type(png, info))
        let channels = Int(png_get_channels(png, info))
        let updatedBitDepth = Int32(png_get_bit_depth(png, info))

        let bytesPerSample = (updatedBitDepth == 16) ? 2 : 1
        let rowBytes = Int(width) * channels * bytesPerSample

        var rowBuffer = [UInt8](repeating: 0, count: rowBytes)
        let pixelCount = Int(width) * Int(height)
        let outDepth: ImageBuffer.BitDepth = (updatedBitDepth == 16) ? .sixteen : .eight
        var rgb = Data(count: pixelCount * 3 * bytesPerSample)

        try rgb.withUnsafeMutableBytes { (rawDest: UnsafeMutableRawBufferPointer) in
            let destBase = rawDest.baseAddress!
            for row in 0..<Int(height) {
                try rowBuffer.withUnsafeMutableBufferPointer { rowPtr in
                    png_read_row(png, rowPtr.baseAddress, nil)
                }

                if updatedBitDepth == 16 {
                    rowBuffer.withUnsafeBufferPointer { srcBytes in
                        let src = UnsafeRawPointer(srcBytes.baseAddress!).assumingMemoryBound(to: UInt16.self)
                        let dst = (destBase + row * Int(width) * 3 * 2).assumingMemoryBound(to: UInt16.self)
                        compositeRow16(src: src, dst: dst, width: Int(width),
                                        channels: channels, colorType: updatedColorType)
                    }
                } else {
                    rowBuffer.withUnsafeBufferPointer { srcBytes in
                        let src = srcBytes.baseAddress!
                        let dst = (destBase + row * Int(width) * 3).assumingMemoryBound(to: UInt8.self)
                        compositeRow8(src: src, dst: dst, width: Int(width),
                                       channels: channels, colorType: updatedColorType)
                    }
                }
            }
        }

        png_read_end(png, nil)

        return ImageBuffer(width: Int(width), height: Int(height),
                           bitDepth: outDepth, pixels: rgb)
    }

    // MARK: - Row compositing

    private static func compositeRow8(src: UnsafePointer<UInt8>,
                                       dst: UnsafeMutablePointer<UInt8>,
                                       width: Int,
                                       channels: Int,
                                       colorType: Int32) {
        let hasAlpha = (colorType & PNG_COLOR_MASK_ALPHA) != 0
        if !hasAlpha && channels == 3 {
            memcpy(dst, src, width * 3)
            return
        }
        for x in 0..<width {
            let r = src[x*channels + 0]
            let g = src[x*channels + 1]
            let b = src[x*channels + 2]
            if hasAlpha {
                let a = src[x*channels + 3]
                if a == 255 {
                    dst[x*3 + 0] = r
                    dst[x*3 + 1] = g
                    dst[x*3 + 2] = b
                } else {
                    let af = Float(a) / 255.0
                    let inv = 1.0 - af
                    dst[x*3 + 0] = UInt8(min(255, max(0, Int(Float(r) * af + 255.0 * inv + 0.5))))
                    dst[x*3 + 1] = UInt8(min(255, max(0, Int(Float(g) * af + 255.0 * inv + 0.5))))
                    dst[x*3 + 2] = UInt8(min(255, max(0, Int(Float(b) * af + 255.0 * inv + 0.5))))
                }
            } else {
                dst[x*3 + 0] = r
                dst[x*3 + 1] = g
                dst[x*3 + 2] = b
            }
        }
    }

    private static func compositeRow16(src: UnsafePointer<UInt16>,
                                        dst: UnsafeMutablePointer<UInt16>,
                                        width: Int,
                                        channels: Int,
                                        colorType: Int32) {
        let hasAlpha = (colorType & PNG_COLOR_MASK_ALPHA) != 0
        if !hasAlpha && channels == 3 {
            memcpy(dst, src, width * 3 * 2)
            return
        }
        for x in 0..<width {
            let r = src[x*channels + 0]
            let g = src[x*channels + 1]
            let b = src[x*channels + 2]
            if hasAlpha {
                let a = src[x*channels + 3]
                if a == 65535 {
                    dst[x*3 + 0] = r
                    dst[x*3 + 1] = g
                    dst[x*3 + 2] = b
                } else {
                    let af = Float(a) / 65535.0
                    let inv = 1.0 - af
                    dst[x*3 + 0] = UInt16(min(65535, max(0, Int(Float(r) * af + 65535.0 * inv + 0.5))))
                    dst[x*3 + 1] = UInt16(min(65535, max(0, Int(Float(g) * af + 65535.0 * inv + 0.5))))
                    dst[x*3 + 2] = UInt16(min(65535, max(0, Int(Float(b) * af + 65535.0 * inv + 0.5))))
                }
            } else {
                dst[x*3 + 0] = r
                dst[x*3 + 1] = g
                dst[x*3 + 2] = b
            }
        }
    }
}
