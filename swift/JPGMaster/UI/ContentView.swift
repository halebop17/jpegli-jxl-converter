import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            switch state.phase {
            case .setup:
                SetupView()
            case .running, .done:
                ConversionView()
            }
        }
        .onAppear { state.rescan() }
    }
}
