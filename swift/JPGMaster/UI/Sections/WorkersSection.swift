import SwiftUI

/// Section 5 in the design — "Performance".
struct WorkersSection: View {
    @EnvironmentObject var state: AppState

    private static let options: [DLSegmentedOption<Int>] = [
        .init(value: 1, label: "1  Sequential"),
        .init(value: 2, label: "2  Recommended"),
        .init(value: 4, label: "4  Fast"),
        .init(value: 6, label: "6  Fastest"),
    ]

    var body: some View {
        DLSection(number: "5", title: "Performance", accent: Theme.purple, accentSoft: Theme.purpleSoft) {
            DLSegmented(options: Self.options,
                        selection: $state.workerCount,
                        accent: Theme.purple)
        }
    }
}
