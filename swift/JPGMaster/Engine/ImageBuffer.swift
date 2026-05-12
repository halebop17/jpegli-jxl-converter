import Foundation

/// In-memory pixel buffer used as the exchange format between readers,
/// processors, and writers in the conversion pipeline.
///
/// Layout: contiguous, row-major, RGB interleaved. No padding between rows.
/// Bit depth is uint8 or uint16. uint16 samples are stored in host byte
/// order; the PNG writer is responsible for byte-swapping on disk.
///
/// This mirrors the Python pipeline's normalised numpy array
/// (`(H, W, 3)` with dtype `uint8` or `uint16`).
struct ImageBuffer {

    enum BitDepth {
        case eight
        case sixteen

        var bytesPerSample: Int {
            switch self {
            case .eight:   return 1
            case .sixteen: return 2
            }
        }
    }

    let width: Int
    let height: Int
    let bitDepth: BitDepth

    /// Tightly packed RGB pixel data. Length = width * height * 3 * bytesPerSample.
    var pixels: Data

    var rowStride: Int { width * 3 * bitDepth.bytesPerSample }
    var samplesPerPixel: Int { 3 }

    init(width: Int, height: Int, bitDepth: BitDepth, pixels: Data) {
        precondition(pixels.count == width * height * 3 * bitDepth.bytesPerSample,
                     "pixel buffer size mismatch")
        self.width = width
        self.height = height
        self.bitDepth = bitDepth
        self.pixels = pixels
    }

    /// Allocate a zero-filled buffer with the given dimensions.
    static func zeroed(width: Int, height: Int, bitDepth: BitDepth) -> ImageBuffer {
        let size = width * height * 3 * bitDepth.bytesPerSample
        return ImageBuffer(width: width,
                           height: height,
                           bitDepth: bitDepth,
                           pixels: Data(count: size))
    }
}
