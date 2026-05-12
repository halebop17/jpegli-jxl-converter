import Foundation
import SwiftUI
import Combine

/// Top-level UI state. Mirrors the Python `ConverterApp` `tk.Variable` set
/// — kept compact so SwiftUI views can bind to specific fields without
/// pulling the entire pipeline into the view layer.
@MainActor
final class AppState: ObservableObject {

    // MARK: Mode / paths

    enum InputMode: String, CaseIterable, Identifiable {
        case singleFile  = "file"
        case singleFolder = "folder"
        case recursive   = "tree"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .singleFile:   return "Single File"
            case .singleFolder: return "Single Folder"
            case .recursive:    return "All Subfolders"
            }
        }
    }

    @Published var mode: InputMode = .singleFolder
    @Published var inputFile: URL?
    @Published var inputFolder: URL?
    @Published var outputFolder: URL?
    @Published var mirrorTree: Bool = false

    // MARK: Conversion settings

    @Published var format: ConversionSettings.ExportFormat = .jpeg
    @Published var quality: Double = 85
    @Published var jxlEffort: Double = 7
    @Published var stripMetadata: Bool = false

    @Published var resizeEnabled: Bool = false
    @Published var resizeMode: ResizeOperation.Mode = .longEdge
    @Published var resizeValue: String = "3000"
    @Published var resizeWidth: String = "3000"
    @Published var resizeHeight: String = "2000"

    @Published var workerCount: Int = 2

    // MARK: Discovered files

    @Published var discoveredFiles: [URL] = []

    // MARK: View phase

    enum Phase { case setup; case running; case done }
    @Published var phase: Phase = .setup

    // MARK: Worker pool

    @Published var pool = WorkerPool()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Forward pool's changes so SwiftUI views observing AppState
        // also re-render when @Published properties on pool change.
        pool.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: Encoder availability

    let encoders = EncoderResolver.shared
    var hasCjpegli: Bool { encoders.cjpegli != nil }
    var hasCjxl: Bool    { encoders.cjxl != nil }
    var hasDjxl: Bool    { encoders.djxl != nil }

    // ────────────────────────────────────────────────────────────────────
    // Derived values
    // ────────────────────────────────────────────────────────────────────

    func acceptedSuffixes() -> Set<String> {
        var settings = ConversionSettings()
        settings.format = format
        return settings.acceptedSourceSuffixes()
    }

    func currentScanRoot() -> URL? {
        switch mode {
        case .singleFile:    return inputFile
        case .singleFolder, .recursive: return inputFolder
        }
    }

    func rescan() {
        let suffixes = acceptedSuffixes()
        let scannerMode: FileScanner.Mode? = {
            switch mode {
            case .singleFile:
                guard let url = inputFile else { return nil }
                return .singleFile(url)
            case .singleFolder:
                guard let url = inputFolder else { return nil }
                return .singleFolder(url)
            case .recursive:
                guard let url = inputFolder else { return nil }
                return .recursiveFolder(url)
            }
        }()
        guard let scannerMode else {
            discoveredFiles = []
            return
        }
        discoveredFiles = FileScanner.scan(mode: scannerMode, accepting: suffixes)
    }

    // ────────────────────────────────────────────────────────────────────
    // Validation
    // ────────────────────────────────────────────────────────────────────

    enum StartError: LocalizedError {
        case noFiles
        case missingOutput
        case invalidResize(String)
        case missingEncoder(String)
        case djxlMissingForJxlInput

        var errorDescription: String? {
            switch self {
            case .noFiles: return "No files found for the selected mode."
            case .missingOutput: return "Please choose an output folder."
            case .invalidResize(let detail): return "Invalid resize setting: \(detail)"
            case .missingEncoder(let tool): return "\(tool) was not found."
            case .djxlMissingForJxlInput:
                return "djxl is required to reconstruct JPEG from JXL files but was not found."
            }
        }
    }

    func resolveResizeParams() throws -> ResizeOperation.Parameters? {
        guard resizeEnabled else { return nil }
        switch resizeMode {
        case .widthHeight:
            guard let w = Int(resizeWidth), w > 0,
                  let h = Int(resizeHeight), h > 0 else {
                throw StartError.invalidResize("width and height must be positive integers")
            }
            return ResizeOperation.Parameters(mode: .widthHeight, value: 0, width: w, height: h)
        case .percentage, .longEdge, .shortEdge:
            guard let v = Int(resizeValue), v > 0 else {
                throw StartError.invalidResize("\(resizeMode.label) must be a positive integer")
            }
            return ResizeOperation.Parameters(mode: resizeMode, value: v, width: 0, height: 0)
        }
    }

    func makeSettings() throws -> ConversionSettings {
        var s = ConversionSettings()
        s.format         = format
        s.quality        = Int(quality.rounded())
        s.jxlEffort      = Int(jxlEffort.rounded())
        s.stripMetadata  = stripMetadata
        s.resize         = try resolveResizeParams()
        return s
    }

    func validateForStart() throws {
        if discoveredFiles.isEmpty {
            throw StartError.noFiles
        }
        switch mode {
        case .singleFolder where outputFolder == nil:
            throw StartError.missingOutput
        case .recursive where mirrorTree && outputFolder == nil:
            throw StartError.missingOutput
        default: break
        }
        if format == .jxl && !hasCjxl { throw StartError.missingEncoder("cjxl") }
        if format == .jpeg && !hasCjpegli { throw StartError.missingEncoder("cjpegli") }
        if format == .jpeg && !hasDjxl {
            let hasJxlInput = discoveredFiles.contains { $0.pathExtension.lowercased() == "jxl" }
            if hasJxlInput { throw StartError.djxlMissingForJxlInput }
        }
        _ = try resolveResizeParams()
    }

    // ────────────────────────────────────────────────────────────────────
    // Conversion lifecycle
    // ────────────────────────────────────────────────────────────────────

    func startConversion() async throws {
        try validateForStart()
        let settings = try makeSettings()
        let plannerMode = currentPlannerMode()

        let items = discoveredFiles.map {
            WorkerPool.Item(
                source: $0,
                destination: OutputPathPlanner.planDestination(
                    for: $0,
                    mode: plannerMode,
                    fileExtension: settings.format.fileExtension)
            )
        }
        pool.setItems(items)
        phase = .running
        await pool.run(workerCount: workerCount, settings: settings, encoders: encoders)
        phase = .done
    }

    private func currentPlannerMode() -> OutputPathPlanner.Mode {
        switch mode {
        case .singleFile:
            return .singleFile
        case .singleFolder:
            let out = outputFolder ?? defaultOutputFolderForFolderMode()
            return .singleFolder(outputDir: out)
        case .recursive:
            let root = inputFolder ?? URL(fileURLWithPath: "/")
            return .recursiveFolder(rootInputDir: root,
                                     outputDir: outputFolder,
                                     mirror: mirrorTree)
        }
    }

    private func defaultOutputFolderForFolderMode() -> URL {
        if let dir = inputFolder {
            return dir.appendingPathComponent("converted", isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("converted", isDirectory: true)
    }

    func cancel() {
        pool.cancel()
    }

    func backToSetup() {
        phase = .setup
    }
}
