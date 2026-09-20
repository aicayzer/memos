import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel

    override init() {
        do {
            model = AppModel(store: try JSONMemoStore.inApplicationSupport())
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
