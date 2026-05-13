import SwiftUI

@main
struct ArtworkDocumenterApp: App {
    @State private var projectState  = ProjectState()
    @State private var exportSettings = ExportSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(projectState)
                .environment(exportSettings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 820, height: 700)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
