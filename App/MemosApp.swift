import SwiftUI

@main
struct MemosApp: App {
    var body: some Scene {
        Window(Bundle.main.displayName, id: "main") {
            MainView()
                .frame(minWidth: 320, minHeight: 240)
        }
        .defaultSize(width: 520, height: 640)
        .windowResizability(.contentMinSize)

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
