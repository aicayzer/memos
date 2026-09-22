import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var panel: MemoPanel?
    private var watcher: LibraryWatcher?
    let updater = Updater()

    /// The test host must not touch the real store or defaults, and must not hand over to a running app.
    private static let isTestHost = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }

    override init() {
        let store: LibraryStore
        do {
            if Self.isTestHost {
                store = LibraryStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString).json"))
                model = AppModel(
                    store: store, images: store,
                    defaults: UserDefaults(suiteName: "tests")!
                )
            } else {
                // Another file, inside the container, for a run that must not show the real memos.
                store = try LibraryStore.inApplicationSupport()
                model = AppModel(store: store, images: store)
            }
        } catch {
            fatalError("memo store unavailable: \(error)")
        }
        super.init()
        watcher = LibraryWatcher(store: store) { [model] in model.storeChanged() } onError: { [model] message in model.storageError = message }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Two instances on one store overwrite each other's saves, so a second launch hands over to the first.
        // Done here rather than with the Info.plist key, which would also stop the test host while the app runs.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other = others.first, !Self.isTestHost {
            other.activate()
            NSApp.terminate(nil)
            return
        }
        model.applyActivationPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("launched")
        let panel = MemoPanel(content: MainView().environment(model))
        panel.keys = { [model] in model.shortcuts.windowKeys }
        panel.perform = { [model] in model.perform($0) }
        self.panel = panel
        model.attach(panel)
        model.showWindow()
        KeyboardShortcuts.onKeyDown(for: .toggleWindow) { [model] in model.toggleWindow() }
        KeyboardShortcuts.onKeyDown(for: .newMemo) { [model] in Task { await model.newMemo() } }
        updater.start()
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
