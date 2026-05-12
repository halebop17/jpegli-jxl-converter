import Foundation

/// Swift-facing wrapper around the ObjC++ libexiv2 bridge. Captures
/// EXIF / IPTC / XMP / ICC metadata from a source file and re-applies it
/// to a destination file, replacing the destination's existing metadata.
///
/// Mirrors the Python pipeline's exiftool-driven metadata transfer.
enum MetadataTransfer {

    /// Captured metadata wrapper around `ExivCapturedMetadata`.
    struct Captured {
        fileprivate let underlying: ExivCapturedMetadata
        var isEmpty: Bool { underlying.isEmpty }
    }

    /// Read EXIF/IPTC/XMP/ICC from a source file. Returns nil when the file
    /// has no metadata or libexiv2 cannot parse it (which is non-fatal —
    /// the conversion proceeds without metadata transfer).
    static func capture(from url: URL) -> Captured? {
        // Swift bridges the trailing NSError** out-parameter into a Swift
        // `throws` — call without the error arg and handle via try?.
        guard let captured = try? ExivBridge.readMetadata(fromPath: url.path) else {
            return nil
        }
        if captured.isEmpty { return nil }
        return Captured(underlying: captured)
    }

    /// Write captured metadata into a destination file.
    /// Throws on non-recoverable libexiv2 errors. Format-mismatch warnings
    /// (e.g. IPTC into JXL) are silently absorbed by the bridge.
    static func apply(_ captured: Captured, to url: URL) throws {
        do {
            try ExivBridge.write(captured.underlying, toPath: url.path)
        } catch {
            throw PipelineError.metadataFailed(error.localizedDescription)
        }
    }

    /// Strip all EXIF/IPTC/XMP from a file. ICC profile remains.
    static func strip(at url: URL) throws {
        do {
            try ExivBridge.stripMetadata(atPath: url.path)
        } catch {
            throw PipelineError.metadataFailed(error.localizedDescription)
        }
    }
}
