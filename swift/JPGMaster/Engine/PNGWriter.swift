import Foundation
import CPng

/// libpng-backed PNG writer used to produce the temporary intermediary PNG
/// that `cjpegli` and `cjxl` consume. Bit depth is preserved exactly:
/// uint8 buffer → 8-bit PNG; uint16 buffer → 16-bit PNG.
enum PNGWriter {

    static func writeTemp(_ buffer: ImageBuffer) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpURL = tmpDir.appendingPathComponent("jpgmaster-\(UUID().uuidString).png")
        try write(buffer, to: tmpURL)
        return tmpURL
    }

    static func write(_ buffer: ImageBuffer, to url: URL) throws {
        guard let fp = fopen(url.path, "wb") else {
            throw PipelineError.writeFailed(url, "fopen failed")
        }
        defer { fclose(fp) }

        guard let png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nil, nil, nil) else {
            throw PipelineError.writeFailed(url, "png_create_write_struct failed")
        }
        guard let info = png_create_info_struct(png) else {
            var p: png_structp? = png
            png_destroy_write_struct(&p, nil)
            throw PipelineError.writeFailed(url, "png_create_info_struct failed")
        }
        defer {
            var p: png_structp? = png
            var i: png_infop? = info
            png_destroy_write_struct(&p, &i)
        }

        png_init_io(png, fp)

        let bitDepth: Int32 = (buffer.bitDepth == .sixteen) ? 16 : 8
        png_set_IHDR(png, info,
                     png_uint_32(buffer.width), png_uint_32(buffer.height),
                     bitDepth,
                     PNG_COLOR_TYPE_RGB,
                     PNG_INTERLACE_NONE,
                     PNG_COMPRESSION_TYPE_DEFAULT,
                     PNG_FILTER_TYPE_DEFAULT)

        png_write_info(png, info)

        // libpng expects 16-bit samples in network byte order. Our internal
        // buffer is host-order; tell libpng to swap on the fly.
        if buffer.bitDepth == .sixteen {
            png_set_swap(png)
        }

        let bytesPerSample = buffer.bitDepth.bytesPerSample
        let rowStride = buffer.width * 3 * bytesPerSample

        buffer.pixels.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for row in 0..<buffer.height {
                let rowPtr = UnsafeMutablePointer<UInt8>(mutating: base + row * rowStride)
                png_write_row(png, rowPtr)
            }
        }

        png_write_end(png, nil)
    }
}
