import Foundation

enum PipelineError: LocalizedError {
    case readFailed(URL, String)
    case writeFailed(URL, String)
    case unsupportedFormat(URL)
    case encoderMissing(String)
    case encoderFailed(tool: String, exitCode: Int32, stderr: String)
    case cancelled
    case invalidInput(String)
    case metadataFailed(String)

    var errorDescription: String? {
        switch self {
        case .readFailed(let url, let detail):
            return "Failed to read \(url.lastPathComponent): \(detail)"
        case .writeFailed(let url, let detail):
            return "Failed to write \(url.lastPathComponent): \(detail)"
        case .unsupportedFormat(let url):
            return "Unsupported source format: \(url.lastPathComponent)"
        case .encoderMissing(let tool):
            return "\(tool) was not found"
        case .encoderFailed(let tool, let code, let stderr):
            let snippet = stderr.isEmpty ? "" : " — \(stderr.prefix(400))"
            return "\(tool) failed (exit \(code))\(snippet)"
        case .cancelled:
            return "Conversion was cancelled"
        case .invalidInput(let detail):
            return detail
        case .metadataFailed(let detail):
            return "Metadata transfer failed: \(detail)"
        }
    }
}
