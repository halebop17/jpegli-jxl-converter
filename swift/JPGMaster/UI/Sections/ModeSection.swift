import SwiftUI

struct ModeSection: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        DLSection(number: "1", title: "Mode", accent: Theme.cyan, accentSoft: Theme.cyanSoft) {
            DLSegmented(
                options: AppState.InputMode.allCases.map {
                    DLSegmentedOption(value: $0, label: $0.label)
                },
                selection: Binding(
                    get: { state.mode },
                    set: { newValue in
                        state.mode = newValue
                        if state.mode != .recursive { state.mirrorTree = false }
                        state.rescan()
                    }
                ),
                accent: Theme.cyan
            )
        }
    }
}
