import SwiftUI

@main
struct MemosApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    private var model: AppModel { delegate.model }

    // The memo window is the delegate's panel, not a scene; the commands hang off Settings.
    var body: some Scene {
        Settings {
            SettingsView()
                .environment(model)
                .environment(delegate.updater)
        }
        .commands { AppCommands(model: model, updater: delegate.updater) }

        MenuBarExtra(Bundle.main.displayName, systemImage: "scribble", isInserted: Binding(
            get: { model.menuBarItem }, set: { model.menuBarItem = $0 }
        )) {
            Button("Open \(Bundle.main.displayName)") { model.showWindow() }
            Button("New Memo") { Task { await model.newMemo() } }
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

    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}
