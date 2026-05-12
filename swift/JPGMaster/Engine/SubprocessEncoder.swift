import Foundation

/// Typed wrapper around `Process` for invoking the bundled CLI encoders.
/// The CLI is the stable API surface for `cjpegli`/`cjxl`/`djxl` — linking
/// the libraries directly is explicitly unsupported. Subprocess isolation
/// also means an encoder crash cannot bring down the app.
enum SubprocessEncoder {

    /// Invoke `cjpegli <src> <dst> --quality=<q>`. Throws on non-zero exit.
    static func runCjpegli(binary: URL, input: URL, output: URL, quality: Int) throws {
        let args = [
            input.path,
            output.path,
            "--quality=\(quality)",
        ]
        try run(tool: "cjpegli", binary: binary, arguments: args)
    }

    /// Invoke `cjxl <src> <dst> --quality=<q> --effort=<e> --container=1 --quiet`.
    static func runCjxl(binary: URL, input: URL, output: URL,
                         quality: Int, effort: Int) throws {
        let args = [
            input.path,
            output.path,
            "--quality=\(quality)",
            "--effort=\(effort)",
            "--container=1",
            "--quiet",
        ]
        try run(tool: "cjxl", binary: binary, arguments: args)
    }

    /// JPEG → JXL lossless transcode. Bit-exact reconstruction available
    /// later via `djxl`.
    static func runCjxlLosslessJpeg(binary: URL, input: URL, output: URL) throws {
        let args = [
            input.path,
            output.path,
            "--lossless_jpeg=1",
            "--container=1",
            "--quiet",
        ]
        try run(tool: "cjxl", binary: binary, arguments: args)
    }

    /// JXL → JPEG round-trip reconstruction (`djxl src dst`).
    static func runDjxl(binary: URL, input: URL, output: URL) throws {
        try run(tool: "djxl", binary: binary, arguments: [input.path, output.path])
    }

    // MARK: -

    private static func run(tool: String, binary: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set DYLD_LIBRARY_PATH so cjpegli / cjxl find their bundled dylibs
        // when invoked from inside the .app bundle.
        if let resourceURL = Bundle.main.resourceURL {
            let dylibDir = resourceURL.appendingPathComponent("bin").path
            var env = ProcessInfo.processInfo.environment
            env["DYLD_LIBRARY_PATH"] = [env["DYLD_LIBRARY_PATH"], dylibDir]
                .compactMap { $0 }
                .joined(separator: ":")
            process.environment = env
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw PipelineError.encoderFailed(tool: tool,
                                              exitCode: process.terminationStatus,
                                              stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Drain pipes to avoid resource leaks.
        _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    }
}
