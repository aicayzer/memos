import SwiftUI

@main
struct MemosApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window(Bundle.main.displayName, id: "main") {
            MainView()
                .frame(minWidth: 320, minHeight: 240)
                .environment(model)
        }
        .defaultSize(width: 520, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Memo") { Task { await model.newMemo() } }
                    .keyboardShortcut("n")
            }
        }

        Settings {
            Form {}
                .formStyle(.grouped)
                .frame(width: 420)
        }
    }
}

extension Bundle {
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
    }
}
