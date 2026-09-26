import SwiftUI

@main
struct DriveviewerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("driveviewer", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1060, minHeight: 760)
                .preferredColorScheme(.dark)
                .background(MenuBarInstaller(model: model))
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Folder or Drive") { model.chooseLocation() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Scan") { model.refresh() }
                    .keyboardShortcut("r")
                Button("Show in Finder") { model.revealCurrent() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Full Disk Access Settings") { model.openFullDiskAccessSettings() }
            }
        }
    }
}

private struct MenuBarInstaller: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.frame(width: 1, height: 1).onAppear {
            MenuBarController.shared.install(model: model) {
                openWindow(id: "main")
            }
        }
    }
}
