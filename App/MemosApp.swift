import SwiftUI

@main
struct MemosApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window(Bundle.main.displayName, id: "main") {
            MainView()
                .frame(minWidth: 400, minHeight: 240)
                .environment(model)
        }
        .defaultSize(width: 520, height: 640)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(Bundle.main.displayName, systemImage: "scribble", isInserted: Binding(
            get: { model.menuBarItem }, set: { model.menuBarItem = $0 }
        )) {
            Button("Open \(Bundle.main.displayName)") { model.showWindow() }
            Button("New Memo") {
                // A status item click does not activate the app, and a hidden app cannot open a window.
                model.showWindow()
                Task { await model.newMemo() }
            }
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit \(Bundle.main.displayName)") { NSApp.terminate(nil) }
        }
    }
}

extension Bundle {
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
    }
}
