import Foundation

/// Locates `cjpegli`, `cjxl`, and `djxl` binaries. Bundled binaries inside
/// `Contents/Resources/bin/` take precedence; falls back to common system
/// install paths so a developer build (without bundling) still works.
struct EncoderResolver {

    let cjpegli: URL?
    let cjxl: URL?
    let djxl: URL?

    static let shared: EncoderResolver = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
        let systemPaths = ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(fileURLWithPath: $0) }
        return EncoderResolver(cjpegli: locate("cjpegli", bundled: bundled, system: systemPaths),
                               cjxl:    locate("cjxl",    bundled: bundled, system: systemPaths),
                               djxl:    locate("djxl",    bundled: bundled, system: systemPaths))
    }()

    private static func locate(_ name: String,
                                bundled: URL?,
                                system: [URL]) -> URL? {
        if let bundled = bundled {
            let candidate = bundled.appendingPathComponent(name)
            if isExecutable(candidate) { return candidate }
        }
        for dir in system {
            let candidate = dir.appendingPathComponent(name)
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    private static func isExecutable(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
        return fm.isExecutableFile(atPath: url.path)
    }
}
