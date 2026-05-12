import SwiftUI

struct FileListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Files found")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.text)
                Spacer()
                HStack(spacing: 6) {
                    Text("\(state.discoveredFiles.count)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.text)
                    Text("ready")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textDim)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.panel)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)

                if state.discoveredFiles.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.textFaint)
                        Text("No files yet")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textDim)
                        Text("Choose an input folder or file in step 2")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(Theme.textFaint)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.discoveredFiles, id: \.self) { url in
                                DLFileRow(name: displayName(for: url))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)

            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.green)
                    .frame(width: 6, height: 6)
                Text(statusFooter)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 4)
        }
    }

    private var statusFooter: String {
        let out = state.outputFolder?.path
            ?? state.inputFolder?.appendingPathComponent("converted").path
            ?? "—"
        return "Idle  ·  output → \(out)"
    }

    private func displayName(for url: URL) -> String {
        if state.mode == .recursive, let root = state.inputFolder {
            return url.path.replacingOccurrences(of: root.path + "/", with: "")
        }
        return url.lastPathComponent
    }
}
