import SwiftUI

struct SetupView: View {
    @EnvironmentObject var state: AppState
    @State private var startError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.panel2)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    // MARK: - Left column: hero + 5 sections + CTA

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero.padding(.bottom, 4)
                ModeSection()
                InputSection()
                FormatSection()
                MetadataSection()
                WorkersSection()
                DLPrimaryButton(
                    title: "Convert",
                    subtitle: convertSubtitle,
                    enabled: startEnabled,
                    action: startConversion
                )
                .padding(.top, 4)
                if let err = startError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.top, 2)
                }
                if !startEnabled {
                    Text(disabledReason)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(Theme.textDim)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            AppIconView(size: 56, radius: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("JPG Master")
                    .font(.system(size: 22, weight: .bold))
                    .kerning(-0.3)
                    .foregroundColor(Theme.text)
                Text("Convert TIFF · PNG · JXL → JPEG, with metadata intact")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.textDim)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Right column: flow hero (40%) + file list (60%)

    private var rightColumn: some View {
        GeometryReader { geo in
            let totalH = geo.size.height - 22 * 2 - 14
            let topH = max(220, totalH * 0.40)
            VStack(spacing: 14) {
                FlowHeroView()
                    .frame(height: topH)
                FileListView()
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }

    // MARK: - Convert button state

    private var convertSubtitle: String? {
        let n = state.discoveredFiles.count
        guard n > 0 else { return nil }
        return "\(n) file\(n == 1 ? "" : "s")"
    }

    private var startEnabled: Bool {
        guard !state.discoveredFiles.isEmpty else { return false }
        if state.format == .jpeg { return state.hasCjpegli }
        if state.format == .jxl  { return state.hasCjxl }
        return false
    }

    private var disabledReason: String {
        if state.discoveredFiles.isEmpty {
            return "Choose an input folder or file to begin."
        }
        if state.format == .jpeg && !state.hasCjpegli { return "cjpegli encoder not found." }
        if state.format == .jxl  && !state.hasCjxl    { return "cjxl encoder not found." }
        return ""
    }

    private func startConversion() {
        startError = nil
        Task {
            do {
                try await state.startConversion()
            } catch {
                startError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}
