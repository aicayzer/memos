import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel

    override init() {
        do {
            // The test host must not touch the real store or defaults.
            if ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("XCTest") }) {
                let file = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString).json")
                model = AppModel(store: try JSONMemoStore(fileURL: file), defaults: UserDefaults(suiteName: "tests")!)
            } else {
                model = AppModel(store: try JSONMemoStore.inApplicationSupport())
            }
        } catch {
            fatalError("memo store unavailable: \(error)")
        }
        super.init()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            sender.reply(toApplicationShouldTerminate: await model.flush())
        }
        return .terminateLater
    }
}
