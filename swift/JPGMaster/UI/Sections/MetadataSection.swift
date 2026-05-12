import SwiftUI

/// Section 4 in the design — "Image & Metadata".
struct MetadataSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        DLSection(number: "4", title: "Image & Metadata", accent: Theme.cyan, accentSoft: Theme.cyanSoft) {
            DLCheckbox(
                isOn: $state.resizeEnabled,
                label: "Resize images",
                hint: state.resizeEnabled ? nil : "Keep originals at full resolution"
            )
            if state.resizeEnabled {
                resizeControls
                    .padding(.leading, 28)
            }

            DLCheckbox(
                isOn: $state.stripMetadata,
                label: "Strip all metadata",
                hint: "Remove EXIF, IPTC, XMP, ICC"
            )

            if !state.stripMetadata {
                HStack(spacing: 6) {
                    Text("✓")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                    Text("Metadata transfer enabled · EXIF · IPTC · XMP · ICC")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textDim)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.panel2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var resizeControls: some View {
        HStack(spacing: 8) {
            Picker("", selection: $state.resizeMode) {
                ForEach(ResizeOperation.Mode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            if state.resizeMode == .widthHeight {
                DLCompactField(text: $state.resizeWidth)
                Text("×")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textDim)
                DLCompactField(text: $state.resizeHeight)
                Text("px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textDim)
            } else {
                DLCompactField(text: $state.resizeValue)
                Text(state.resizeMode == .percentage ? "%" : "px")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textDim)
            }
            Spacer(minLength: 0)
        }
    }
}
