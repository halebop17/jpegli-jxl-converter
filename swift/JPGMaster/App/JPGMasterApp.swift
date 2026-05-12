import SwiftUI

@main
struct JPGMasterApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("JPG Master", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1100, minHeight: 820)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
