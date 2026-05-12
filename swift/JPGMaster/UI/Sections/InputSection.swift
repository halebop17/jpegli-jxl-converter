import SwiftUI
import AppKit

/// "Locations" section in the design — input + output paths combined,
/// with the Mirror toggle when in recursive mode.
struct InputSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        DLSection(number: "2", title: "Locations", accent: Theme.purple, accentSoft: Theme.purpleSoft) {
            VStack(alignment: .leading, spacing: 4) {
                DLFieldLabel(text: inputCaption)
                DLPathField(value: inputDisplay, placeholder: inputPlaceholder, onBrowse: pickInput)
            }
            if state.mode != .singleFile {
                VStack(alignment: .leading, spacing: 4) {
                    DLFieldLabel(text: "Output folder")
                    DLPathField(value: outputDisplay,
                                placeholder: outputPlaceholder,
                                onBrowse: pickOutput)
                }
            }
            if state.mode == .recursive {
                DLCheckbox(
                    isOn: $state.mirrorTree,
                    label: "Mirror folder structure to output",
                    hint: "Recreate the input subfolder tree under the output root",
                    accent: Theme.purple
                )
            }
        }
    }

    // MARK: - Input

    private var inputCaption: String {
        let kinds = state.format == .jxl ? "TIFF · PNG · JPEG" : "TIFF · PNG · JXL"
        switch state.mode {
        case .singleFile:    return "Input file · \(kinds)"
        case .singleFolder:  return "Input folder · \(kinds)"
        case .recursive:     return "Input root folder · recursive · \(kinds)"
        }
    }

    private var inputDisplay: String {
        switch state.mode {
        case .singleFile:                return state.inputFile?.path ?? ""
        case .singleFolder, .recursive:  return state.inputFolder?.path ?? ""
        }
    }

    private var inputPlaceholder: String {
        state.mode == .singleFile ? "no file selected" : "no folder selected"
    }

    private func pickInput() {
        let panel = NSOpenPanel()
        switch state.mode {
        case .singleFile:
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsOtherFileTypes = true
            if panel.runModal() == .OK, let url = panel.url {
                state.inputFile = url
                state.inputFolder = url.deletingLastPathComponent()
                state.rescan()
            }
        case .singleFolder, .recursive:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                state.inputFolder = url
                state.inputFile = nil
                if state.mode == .singleFolder && state.outputFolder == nil {
                    state.outputFolder = url.appendingPathComponent("converted",
                                                                     isDirectory: true)
                }
                state.rescan()
            }
        }
    }

    // MARK: - Output

    private var outputDisplay: String { state.outputFolder?.path ?? "" }

    private var outputPlaceholder: String {
        state.mode == .recursive
            ? "defaults to /converted in source folders"
            : "defaults to /converted in source folder"
    }

    private func pickOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            state.outputFolder = url
        }
    }
}
