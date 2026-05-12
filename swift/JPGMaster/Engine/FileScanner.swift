import Foundation

/// Discovers source files for conversion. Matches the Python pipeline's
/// three modes: single file, single folder, recursive folder.
enum FileScanner {

    enum Mode {
        case singleFile(URL)
        case singleFolder(URL)
        case recursiveFolder(URL)
    }

    static func scan(mode: Mode, accepting suffixes: Set<String>) -> [URL] {
        switch mode {
        case .singleFile(let url):
            let ok = FileManager.default.fileExists(atPath: url.path)
                && suffixes.contains(url.pathExtension.lowercased())
            return ok ? [url] : []

        case .singleFolder(let dir):
            return scanFlat(dir: dir, accepting: suffixes).sorted { $0.path < $1.path }

        case .recursiveFolder(let root):
            return scanRecursive(root: root, accepting: suffixes).sorted { $0.path < $1.path }
        }
    }

    private static func scanFlat(dir: URL, accepting suffixes: Set<String>) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir,
                                                         includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries.filter { suffixes.contains($0.pathExtension.lowercased()) }
    }

    private static func scanRecursive(root: URL, accepting suffixes: Set<String>) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                              includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles]) else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator {
            if suffixes.contains(url.pathExtension.lowercased()) {
                results.append(url)
            }
        }
        return results
    }
}
