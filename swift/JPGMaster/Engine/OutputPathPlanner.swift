import Foundation

/// Computes the output URL for each source file based on the chosen mode,
/// output folder, mirror flag and target format. Mirrors the Python
/// `_compute_output_path`.
enum OutputPathPlanner {

    enum Mode {
        case singleFile
        case singleFolder(outputDir: URL)
        case recursiveFolder(rootInputDir: URL, outputDir: URL?, mirror: Bool)
    }

    static func planDestination(for source: URL,
                                 mode: Mode,
                                 fileExtension: String) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        let filename = "\(stem).\(fileExtension)"

        switch mode {
        case .singleFile:
            return source.deletingLastPathComponent().appendingPathComponent(filename)

        case .singleFolder(let outputDir):
            return outputDir.appendingPathComponent(filename)

        case .recursiveFolder(let rootIn, let outputDir, let mirror):
            if mirror, let outputDir = outputDir {
                let relative = source.deletingLastPathComponent()
                    .pathRelative(to: rootIn) ?? ""
                return outputDir
                    .appendingPathComponent(relative, isDirectory: true)
                    .appendingPathComponent(filename)
            }
            // Default: write to <source-folder>/converted/
            return source.deletingLastPathComponent()
                .appendingPathComponent("converted", isDirectory: true)
                .appendingPathComponent(filename)
        }
    }
}

private extension URL {
    /// Compute the path of self relative to `base`, returning nil if it's
    /// not a subpath. Returns "" if self == base.
    func pathRelative(to base: URL) -> String? {
        let baseComponents = base.standardized.pathComponents
        let selfComponents = self.standardized.pathComponents
        guard selfComponents.count >= baseComponents.count else { return nil }
        for i in 0..<baseComponents.count {
            if baseComponents[i] != selfComponents[i] { return nil }
        }
        let tail = selfComponents.dropFirst(baseComponents.count)
        return tail.joined(separator: "/")
    }
}
