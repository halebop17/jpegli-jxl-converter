import Foundation

/// Format and parameters for a single conversion job.
struct ConversionSettings {

    enum ExportFormat: String, CaseIterable, Identifiable {
        case jpeg
        case jxl
        var id: String { rawValue }
        var label: String { self == .jpeg ? "JPEG" : "JXL" }
        var fileExtension: String { self == .jpeg ? "jpg" : "jxl" }
    }

    var format: ExportFormat = .jpeg
    var quality: Int = 85
    var jxlEffort: Int = 7
    var stripMetadata: Bool = false
    var resize: ResizeOperation.Parameters?

    /// Source-format suffixes accepted for the chosen export format,
    /// matching the Python pipeline.
    func acceptedSourceSuffixes() -> Set<String> {
        switch format {
        case .jpeg: return ["tif", "tiff", "png", "jxl"]
        case .jxl:  return ["tif", "tiff", "png", "jpg", "jpeg"]
        }
    }
}
