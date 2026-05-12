import SwiftUI

struct ConversionView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            header

            tableCard
                .frame(maxHeight: .infinity)

            progressBar

            HStack(spacing: 8) {
                if state.pool.isRunning {
                    Button(role: .destructive) { state.cancel() } label: {
                        Label("Cancel", systemImage: "stop.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                } else {
                    Button { state.backToSetup() } label: {
                        Label("Go Back", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cyan)
                    .controlSize(.large)
                }
                Spacer()
                statusChip
            }
            .padding(.horizontal, 4)

            if !state.pool.errors.isEmpty {
                ErrorLogView(errors: state.pool.errors)
                    .frame(height: 110)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(Theme.bg.ignoresSafeArea())
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 14) {
            AppIconView(size: 40, radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(headerText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.text)
                    .kerning(-0.2)
                Text(subText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textDim)
            }
            Spacer()
        }
    }

    private var tableCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white)
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1)
            ConversionTable(items: state.pool.items)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
    }

    private var progressBar: some View {
        HStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panel2).overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0x2CC6DB), Theme.cyan],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * progressFraction))
                }
            }
            .frame(height: 8)
            Text(counterText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textDim)
                .frame(width: 90, alignment: .trailing)
        }
    }

    private var statusChip: some View {
        let (label, color) = phaseChipInfo
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textDim)
        }
    }

    // MARK: - Derived

    private var totalCount: Int { state.pool.items.count }
    private var doneCount: Int  { state.pool.completed + state.pool.failed + state.pool.cancelledCount }

    private var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(doneCount) / Double(totalCount)
    }

    private var counterText: String { "\(doneCount) / \(totalCount)" }

    private var headerText: String {
        if state.pool.isRunning { return "Converting…" }
        let ok = state.pool.completed
        let failed = state.pool.failed
        let cancelled = state.pool.cancelledCount
        if cancelled > 0 && failed == 0 {
            return "Cancelled  ·  \(ok) converted, \(cancelled) cancelled"
        }
        if cancelled > 0 && failed > 0 {
            return "Cancelled  ·  \(ok) converted, \(cancelled) cancelled, \(failed) failed"
        }
        if failed > 0 {
            return "Done  ·  \(ok) converted, \(failed) failed"
        }
        return "Done  ·  \(ok) of \(totalCount) converted successfully"
    }

    private var subText: String {
        if let out = state.outputFolder?.path { return "output → \(out)" }
        return ""
    }

    private var phaseChipInfo: (String, Color) {
        if state.pool.isRunning { return ("Running", Theme.cyan) }
        if state.pool.failed > 0 { return ("Errors", .red) }
        return ("Complete", Theme.green)
    }
}

private struct ConversionTable: View {
    let items: [WorkerPool.Item]

    var body: some View {
        Table(items) {
            TableColumn("Original File") { item in
                Text(item.source.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 12.5, design: .monospaced))
            }
            TableColumn("Status") { item in
                StatusPill(status: item.status)
            }
            .width(min: 110, ideal: 130, max: 160)
            TableColumn("Notes") { item in
                Text(noteText(item.status))
                    .foregroundColor(Theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 11.5, design: .monospaced))
            }
        }
    }

    private func noteText(_ status: WorkerPool.Status) -> String {
        switch status {
        case .failed(let msg): return msg
        default: return ""
        }
    }
}

private struct StatusPill: View {
    let status: WorkerPool.Status
    var body: some View {
        let (label, color) = info
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
    private var info: (String, Color) {
        switch status {
        case .waiting:    return ("Waiting", Theme.textDim)
        case .processing: return ("Running", Theme.cyan)
        case .converted:  return ("Converted", Theme.green)
        case .failed:     return ("Failed", .red)
        case .cancelled:  return ("Cancelled", Theme.textFaint)
        }
    }
}

private struct ErrorLogView: View {
    let errors: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Errors")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.text)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(errors, id: \.self) { e in
                        Text("• \(e)")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(Theme.textDim)
                    }
                }
                .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 1)
            )
        }
    }
}
