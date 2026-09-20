import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel

    override init() {
        do {
            // The test host must not touch the real memos file.
            let isTestHost = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }
            let store = isTestHost
                ? try JSONMemoStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "memos-tests.json"))
                : try JSONMemoStore.inApplicationSupport()
            model = AppModel(store: store)
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
            await model.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
