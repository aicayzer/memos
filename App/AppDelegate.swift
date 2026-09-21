import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var panel: MemoPanel?
    private var watcher: StoreWatcher?

    override init() {
        let store: JSONMemoStore
        do {
            // The test host must not touch the real store or defaults.
            if ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("XCTest") }) {
                store = JSONMemoStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString).json"))
                model = AppModel(store: store, defaults: UserDefaults(suiteName: "tests")!)
            } else {
                store = try JSONMemoStore.inApplicationSupport()
                model = AppModel(store: store)
            }
        } catch {
            fatalError("memo store unavailable: \(error)")
        }
        super.init()
        watcher = StoreWatcher(directory: store.fileURL.deletingLastPathComponent()) { [model] in model.storeChanged() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Two instances on one store overwrite each other's saves, so a second launch hands over to the first.
        // Done here rather than with the Info.plist key, which would also stop the test host while the app runs.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other = others.first, !ProcessInfo.processInfo.environment.keys.contains(where: { $0.hasPrefix("XCTest") }) {
            other.activate()
            NSApp.terminate(nil)
            return
        }
        model.applyActivationPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("launched")
        let panel = MemoPanel(content: MainView().environment(model))
        panel.alternates = { [model] in model.shortcuts.alternates }
        panel.perform = { [model] in model.perform($0) }
        self.panel = panel
        model.attach(panel)
        model.showWindow()
        KeyboardShortcuts.onKeyDown(for: .toggleWindow) { [model] in model.toggleWindow() }
    }

    /// memos://memo/<id> opens that memo; anything else on the scheme just shows the window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.host() == "memo", let id = UUID(uuidString: url.lastPathComponent) {
                Task { await model.open(id) }
            } else {
                model.showWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showWindow()
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        model.applyActivationPolicy()
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
