import SwiftUI

/// Top card on the right column — shows source file types flowing into the
/// chosen target format.
struct FlowHeroView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONVERSION FLOW")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textFaint)
                        .kerning(1.4)
                    Text(headlineText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.text)
                        .kerning(-0.3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(typeBadges, id: \.ext) { item in
                        DLTypePill(ext: item.ext, count: item.count)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                VStack(spacing: 6) {
                    if sourceChips.isEmpty {
                        DLFormatChip(label: "—",
                                     tint: Theme.textFaint,
                                     sub: "no source files")
                    } else {
                        HStack(spacing: 6) {
                            ForEach(sourceChips, id: \.ext) { item in
                                DLFormatChip(label: item.ext.uppercased(),
                                             tint: Theme.extColor(item.ext).fg,
                                             sub: "\(item.count) file\(item.count == 1 ? "" : "s")")
                            }
                        }
                    }
                    Text("SOURCE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textFaint)
                        .kerning(1)
                }
                DLArrow(tint: targetTint)
                VStack(spacing: 6) {
                    DLFormatChip(label: state.format == .jpeg ? "JPG" : "JXL",
                                 tint: targetTint,
                                 sub: "quality \(Int(state.quality.rounded()))",
                                 big: true)
                    Text("TARGET")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(targetTint)
                        .kerning(1)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .background(
                    ZStack {
                        RadialGradient(colors: [Theme.cyan.opacity(0.10), .clear],
                                       center: .topTrailing, startRadius: 0, endRadius: 320)
                        RadialGradient(colors: [Theme.yellow.opacity(0.10), .clear],
                                       center: .bottomLeading, startRadius: 0, endRadius: 320)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
    }

    // MARK: - Derived data

    /// Folds `tif` into `tiff` and `jpg` into `jpeg` so we don't show two
    /// near-identical chips when both spellings appear in the source set.
    private static func canonicalExt(_ raw: String) -> String {
        switch raw {
        case "tif":  return "tiff"
        case "jpg":  return "jpeg"
        default:     return raw
        }
    }

    private var countsByCanonicalExt: [(ext: String, count: Int)] {
        var d: [String: Int] = [:]
        for url in state.discoveredFiles {
            let e = Self.canonicalExt(url.pathExtension.lowercased())
            d[e, default: 0] += 1
        }
        let order = ["png", "jpeg", "jxl", "tiff"]
        return order.compactMap { ext in
            guard let n = d[ext], n > 0 else { return nil }
            return (ext, n)
        }
    }

    private var typeBadges: [(ext: String, count: Int)] { countsByCanonicalExt }

    private var sourceChips: [(ext: String, count: Int)] {
        // The output format is excluded from the source list — it can never
        // be a source of itself (we accept jxl when target is jpeg, and
        // jpeg when target is jxl, but not the same format).
        let exclude = state.format == .jpeg ? "jpeg" : "jxl"
        return countsByCanonicalExt.filter { $0.ext != exclude }
    }

    private var targetTint: Color {
        state.format == .jpeg ? Theme.yellow : Theme.cyan
    }

    private var headlineText: String {
        let n = state.discoveredFiles.count
        if n == 0 {
            return "No files yet — choose an input folder"
        }
        let path = state.currentScanRoot()?.path
        let suffix = path.map { " · \($0)" } ?? ""
        return "\(n) file\(n == 1 ? "" : "s")\(suffix)"
    }
}
