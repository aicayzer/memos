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

        MenuBarExtra(isInserted: Binding(get: { model.menuBarItem }, set: { model.menuBarItem = $0 })) {
            Button("Open \(Bundle.main.displayName)") { model.showWindow() }
            Button("New Memo") { Task { await model.newMemo() } }
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit \(Bundle.main.displayName)") { NSApp.terminate(nil) }
        } label: {
            // The image alone: a label with text beside it draws that text in the menu bar as well.
            if let symbol = model.menuBarIcon.systemImage {
                Image(systemName: symbol).accessibilityLabel(Bundle.main.displayName)
            } else {
                Image(MenuBarIcon.asset).accessibilityLabel(Bundle.main.displayName)
            }
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
