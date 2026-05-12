import Foundation

/// Single-file conversion. Mirrors the Python `convert_tiff` /
/// `convert_to_jxl` / `convert_jxl_to_jpeg` paths exactly:
///
/// - `JPEG → JXL` uses `cjxl --lossless_jpeg=1 --container=1` (no PNG
///   intermediary, no metadata transfer — the JPEG bitstream and metadata
///   are preserved bit-for-bit by cjxl).
/// - `JXL → JPEG` uses `djxl src dst` for round-trip reconstruction (no
///   metadata transfer — JXL stores it inline).
/// - All other paths: read source → optional resize → temp 8/16-bit PNG
///   → cjpegli or cjxl → metadata transfer via libexiv2.
enum ConversionJob {

    static func run(source: URL,
                    destination: URL,
                    settings: ConversionSettings,
                    encoders: EncoderResolver) throws {

        let srcExt = source.pathExtension.lowercased()
        let isJpegSource = srcExt == "jpg" || srcExt == "jpeg"
        let isJxlSource  = srcExt == "jxl"

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        // Special path: JPEG → JXL (lossless transcode).
        if settings.format == .jxl && isJpegSource {
            guard let cjxl = encoders.cjxl else { throw PipelineError.encoderMissing("cjxl") }
            try SubprocessEncoder.runCjxlLosslessJpeg(binary: cjxl, input: source, output: destination)
            return
        }

        // Special path: JXL → JPEG (round-trip reconstruction).
        if settings.format == .jpeg && isJxlSource {
            guard let djxl = encoders.djxl else { throw PipelineError.encoderMissing("djxl") }
            try SubprocessEncoder.runDjxl(binary: djxl, input: source, output: destination)
            return
        }

        // Standard pipeline: read → resize → temp PNG → encode → metadata.
        let captured = settings.stripMetadata ? nil : MetadataTransfer.capture(from: source)

        var buffer = try readSource(source)
        if let params = settings.resize,
           let target = ResizeOperation.targetSize(for: (buffer.width, buffer.height), params: params) {
            buffer = try ResizeOperation.resize(buffer, to: target)
        }

        let tmpPng = try PNGWriter.writeTemp(buffer)
        defer { try? FileManager.default.removeItem(at: tmpPng) }

        switch settings.format {
        case .jpeg:
            guard let cjpegli = encoders.cjpegli else { throw PipelineError.encoderMissing("cjpegli") }
            try SubprocessEncoder.runCjpegli(binary: cjpegli,
                                              input: tmpPng,
                                              output: destination,
                                              quality: settings.quality)
        case .jxl:
            guard let cjxl = encoders.cjxl else { throw PipelineError.encoderMissing("cjxl") }
            try SubprocessEncoder.runCjxl(binary: cjxl,
                                           input: tmpPng,
                                           output: destination,
                                           quality: settings.quality,
                                           effort: settings.jxlEffort)
        }

        // Metadata transfer (best-effort — failure is non-fatal).
        if !settings.stripMetadata, let captured = captured {
            do {
                try MetadataTransfer.apply(captured, to: destination)
            } catch {
                // Log but do not fail — matches the Python pipeline's
                // permissive metadata handling.
                #if DEBUG
                print("metadata transfer warning for \(destination.lastPathComponent): \(error.localizedDescription)")
                #endif
            }
        }
    }

    private static func readSource(_ url: URL) throws -> ImageBuffer {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "tif", "tiff":
            return try TIFFReader.read(url)
        case "png":
            return try PNGReader.read(url)
        default:
            throw PipelineError.unsupportedFormat(url)
        }
    }
}
