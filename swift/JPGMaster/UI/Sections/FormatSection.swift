import SwiftUI

/// Section 3 in the design — "Output" — combines export-format selection,
/// the quality slider, and (for JXL) the encode-effort slider.
struct FormatSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        DLSection(number: "3", title: "Output", accent: Theme.yellow, accentSoft: Theme.yellowSoft) {
            VStack(alignment: .leading, spacing: 6) {
                DLFieldLabel(text: "Export format")
                HStack(spacing: 10) {
                    DLFormatTile(
                        label: "JPEG", sub: "Universal",
                        tint: Theme.yellow, tintSoft: Theme.yellowSoft,
                        active: state.format == .jpeg,
                        onTap: { setFormat(.jpeg) }
                    )
                    DLFormatTile(
                        label: "JXL", sub: "Modern · smaller",
                        tint: Theme.cyan, tintSoft: Theme.cyanSoft,
                        active: state.format == .jxl,
                        onTap: { setFormat(.jxl) }
                    )
                }
                Text(hintText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textFaint)
                    .padding(.top, 6)
            }
            Divider().background(Theme.border)
            qualityBlock
            if state.format == .jxl {
                Divider().background(Theme.border)
                effortBlock
            }
        }
    }

    private func setFormat(_ fmt: ConversionSettings.ExportFormat) {
        guard state.format != fmt else { return }
        state.format = fmt
        state.quality = fmt == .jxl ? 90 : 85
        state.rescan()
    }

    private var hintText: String {
        state.format == .jxl
            ? "TIFF or JPEG  →  JXL  (lossless transcode for JPEG)"
            : "TIFF or JXL   →  JPEG (round-trip reconstruct for JXL)"
    }

    // MARK: - Quality

    private var qualityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                DLFieldLabel(text: "Quality")
                Spacer()
                qualityValueLabel
            }
            DLSlider(value: $state.quality, range: 1...100, step: 1, accent: Theme.yellow)
        }
    }

    private var qualityValueLabel: some View {
        let q = Int(state.quality.rounded())
        return HStack(spacing: 0) {
            Text("\(q)")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.text)
            Text("/100")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textFaint)
            Text("  ·  ")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(Theme.textFaint)
            Text(qualityWord)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.yellow)
        }
    }

    private var qualityWord: String {
        let q = Int(state.quality.rounded())
        if state.format == .jxl {
            switch q {
            case 100:     return "Lossless"
            case 90...99: return "Near-lossless"
            case 75...89: return "High"
            case 68...74: return "Good"
            default:      return "Compressed"
            }
        } else {
            switch q {
            case 90...100: return "Maximum"
            case 70...89:  return "High"
            case 40...69:  return "Balanced"
            default:       return "Smaller"
            }
        }
    }

    // MARK: - JXL effort

    private var effortBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                DLFieldLabel(text: "JXL encode effort")
                Spacer()
                let e = Int(state.jxlEffort.rounded())
                Text("\(e)/9  ·  \(effortHint(e))")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.cyan)
            }
            DLSlider(value: $state.jxlEffort, range: 1...9, step: 1, accent: Theme.cyan)
        }
    }

    private func effortHint(_ e: Int) -> String {
        if e < 7 { return "faster" }
        if e == 7 { return "default" }
        return "slower · smaller"
    }
}
