import Foundation
import Accelerate

/// High-quality Lanczos resampling via Apple's vImage. Operates natively on
/// 8-bit and 16-bit channel data, so the precision of the source buffer
/// is preserved through the resize step (matching what the Python pipeline
/// only approximates by upscaling 8-bit Pillow output back to uint16).
enum ResizeOperation {

    enum Mode: String, CaseIterable, Identifiable {
        case longEdge   = "long_edge"
        case shortEdge  = "short_edge"
        case percentage = "percentage"
        case widthHeight = "wh"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .longEdge:    return "Long Edge"
            case .shortEdge:   return "Short Edge"
            case .percentage:  return "Percentage"
            case .widthHeight: return "Width & Height"
            }
        }
    }

    struct Parameters {
        var mode: Mode
        var value: Int        // for longEdge, shortEdge, percentage
        var width: Int        // for widthHeight
        var height: Int       // for widthHeight
    }

    /// Compute the target dimensions for an image of the given source size,
    /// or return nil if no resize is needed (image already fits).
    static func targetSize(for source: (width: Int, height: Int),
                            params: Parameters) -> (width: Int, height: Int)? {
        switch params.mode {
        case .longEdge:
            let long = max(source.width, source.height)
            if long <= params.value { return nil }
            let scale = Double(params.value) / Double(long)
            return (Int((Double(source.width) * scale).rounded()),
                    Int((Double(source.height) * scale).rounded()))
        case .shortEdge:
            let short = min(source.width, source.height)
            if short <= params.value { return nil }
            let scale = Double(params.value) / Double(short)
            return (Int((Double(source.width) * scale).rounded()),
                    Int((Double(source.height) * scale).rounded()))
        case .percentage:
            if params.value == 100 { return nil }
            let scale = Double(params.value) / 100.0
            return (Int((Double(source.width) * scale).rounded()),
                    Int((Double(source.height) * scale).rounded()))
        case .widthHeight:
            if source.width <= params.width && source.height <= params.height { return nil }
            // Lanczos thumbnail: fit within (W,H), preserving aspect.
            let widthRatio  = Double(params.width)  / Double(source.width)
            let heightRatio = Double(params.height) / Double(source.height)
            let scale = min(widthRatio, heightRatio)
            return (max(1, Int((Double(source.width)  * scale).rounded())),
                    max(1, Int((Double(source.height) * scale).rounded())))
        }
    }

    /// Resample `buffer` to the target size using Lanczos via vImage.
    /// Bit depth is preserved: a 16-bit input produces a 16-bit output.
    static func resize(_ buffer: ImageBuffer, to target: (width: Int, height: Int)) throws -> ImageBuffer {
        switch buffer.bitDepth {
        case .eight:    return try resize8 (buffer: buffer, target: target)
        case .sixteen:  return try resize16(buffer: buffer, target: target)
        }
    }

    // MARK: - 8-bit Lanczos
    //
    // vImage requires RGBA (4 channels) for its convenience scale routines,
    // so we expand RGB → RGBA (alpha=255), resize, then collapse back.

    private static func resize8(buffer: ImageBuffer,
                                 target: (width: Int, height: Int)) throws -> ImageBuffer {
        let srcRGBA = expandRGBtoRGBA8(buffer.pixels, width: buffer.width, height: buffer.height)
        var srcRGBA_mut = srcRGBA

        var srcBuffer = vImage_Buffer()
        srcRGBA_mut.withUnsafeMutableBytes { raw in
            srcBuffer.data     = raw.baseAddress
            srcBuffer.width    = vImagePixelCount(buffer.width)
            srcBuffer.height   = vImagePixelCount(buffer.height)
            srcBuffer.rowBytes = buffer.width * 4
        }

        var dstData = Data(count: target.width * target.height * 4)
        var dstBuffer = vImage_Buffer()
        try dstData.withUnsafeMutableBytes { raw in
            dstBuffer.data     = raw.baseAddress
            dstBuffer.width    = vImagePixelCount(target.width)
            dstBuffer.height   = vImagePixelCount(target.height)
            dstBuffer.rowBytes = target.width * 4
            let err = vImageScale_ARGB8888(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
            if err != kvImageNoError {
                throw PipelineError.invalidInput("vImage scale failed: \(err)")
            }
        }

        let rgb = collapseRGBAtoRGB8(dstData, width: target.width, height: target.height)
        return ImageBuffer(width: target.width, height: target.height, bitDepth: .eight, pixels: rgb)
    }

    private static func expandRGBtoRGBA8(_ rgb: Data, width: Int, height: Int) -> Data {
        var out = Data(count: width * height * 4)
        rgb.withUnsafeBytes { srcRaw in
            out.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.bindMemory(to: UInt8.self).baseAddress,
                      let dst = dstRaw.bindMemory(to: UInt8.self).baseAddress else { return }
                for i in 0..<(width * height) {
                    dst[i*4 + 0] = src[i*3 + 0]
                    dst[i*4 + 1] = src[i*3 + 1]
                    dst[i*4 + 2] = src[i*3 + 2]
                    dst[i*4 + 3] = 255
                }
            }
        }
        return out
    }

    private static func collapseRGBAtoRGB8(_ rgba: Data, width: Int, height: Int) -> Data {
        var out = Data(count: width * height * 3)
        rgba.withUnsafeBytes { srcRaw in
            out.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.bindMemory(to: UInt8.self).baseAddress,
                      let dst = dstRaw.bindMemory(to: UInt8.self).baseAddress else { return }
                for i in 0..<(width * height) {
                    dst[i*3 + 0] = src[i*4 + 0]
                    dst[i*3 + 1] = src[i*4 + 1]
                    dst[i*3 + 2] = src[i*4 + 2]
                }
            }
        }
        return out
    }

    // MARK: - 16-bit Lanczos
    //
    // vImageScale_ARGB16U operates on 16-bit-per-channel ARGB, so the same
    // expand → resize → collapse pattern applies.

    private static func resize16(buffer: ImageBuffer,
                                  target: (width: Int, height: Int)) throws -> ImageBuffer {
        let srcRGBA = expandRGBtoRGBA16(buffer.pixels, width: buffer.width, height: buffer.height)
        var srcRGBA_mut = srcRGBA

        var srcBuffer = vImage_Buffer()
        srcRGBA_mut.withUnsafeMutableBytes { raw in
            srcBuffer.data     = raw.baseAddress
            srcBuffer.width    = vImagePixelCount(buffer.width)
            srcBuffer.height   = vImagePixelCount(buffer.height)
            srcBuffer.rowBytes = buffer.width * 8
        }

        var dstData = Data(count: target.width * target.height * 8)
        var dstBuffer = vImage_Buffer()
        try dstData.withUnsafeMutableBytes { raw in
            dstBuffer.data     = raw.baseAddress
            dstBuffer.width    = vImagePixelCount(target.width)
            dstBuffer.height   = vImagePixelCount(target.height)
            dstBuffer.rowBytes = target.width * 8
            let err = vImageScale_ARGB16U(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
            if err != kvImageNoError {
                throw PipelineError.invalidInput("vImage 16-bit scale failed: \(err)")
            }
        }

        let rgb = collapseRGBAtoRGB16(dstData, width: target.width, height: target.height)
        return ImageBuffer(width: target.width, height: target.height, bitDepth: .sixteen, pixels: rgb)
    }

    private static func expandRGBtoRGBA16(_ rgb: Data, width: Int, height: Int) -> Data {
        var out = Data(count: width * height * 4 * 2)
        rgb.withUnsafeBytes { srcRaw in
            out.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.bindMemory(to: UInt16.self).baseAddress,
                      let dst = dstRaw.bindMemory(to: UInt16.self).baseAddress else { return }
                for i in 0..<(width * height) {
                    dst[i*4 + 0] = src[i*3 + 0]
                    dst[i*4 + 1] = src[i*3 + 1]
                    dst[i*4 + 2] = src[i*3 + 2]
                    dst[i*4 + 3] = 65535
                }
            }
        }
        return out
    }

    private static func collapseRGBAtoRGB16(_ rgba: Data, width: Int, height: Int) -> Data {
        var out = Data(count: width * height * 3 * 2)
        rgba.withUnsafeBytes { srcRaw in
            out.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.bindMemory(to: UInt16.self).baseAddress,
                      let dst = dstRaw.bindMemory(to: UInt16.self).baseAddress else { return }
                for i in 0..<(width * height) {
                    dst[i*3 + 0] = src[i*4 + 0]
                    dst[i*3 + 1] = src[i*4 + 1]
                    dst[i*3 + 2] = src[i*4 + 2]
                }
            }
        }
        return out
    }
}
