import AppKit
import CoreSpotlight
import KeyboardShortcuts
import OSLog
import SwiftUI

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private var panel: MemoPanel?
    private var watcher: LibraryWatcher?
    private var spotlight: SpotlightIndexer?
    private var startup: Task<Void, Never>?
    private var pendingMemoID: UUID?

    /// The test host must not touch the real store or defaults, and must not hand over to a running app.
    private static let isTestHost = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }

    /// One fixed folder, cleared at launch and at exit: a host the test runner kills cannot pile up files.
    private static let testHostFolder = FileManager.default.temporaryDirectory.appending(path: "memos-test-host")

    override init() {
        let store: LibraryStore
        let defaults = Self.isTestHost ? UserDefaults(suiteName: "tests-\(UUID().uuidString)")! : .standard
        do {
            if Self.isTestHost {
                try? FileManager.default.removeItem(at: Self.testHostFolder)
                try FileManager.default.createDirectory(at: Self.testHostFolder, withIntermediateDirectories: true)
                store = LibraryStore(fileURL: Self.testHostFolder.appending(path: "store.json"))
                model = AppModel(
                    store: store, images: store,
                    defaults: defaults
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
        if Self.isTestHost { KeyboardShortcuts.isEnabled = false }
        if !Self.isTestHost {
            spotlight = SpotlightIndexer(store: store, index: SystemMemoSearchIndex()) { [model] in model.spotlightError = $0 }
        }
        watcher = LibraryWatcher(store: store) { [weak self, model] in
            model.storeChanged()
            self?.spotlight?.refresh()
        } onError: { [model] message in model.storageError = message }
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
        let panel = MemoPanel(content: MainView().environment(model), restoresFrame: !Self.isTestHost)
        panel.keys = { [model] in model.shortcuts.windowKeys }
        panel.perform = { [model] in model.perform($0) }
        self.panel = panel
        model.attach(panel)
        if !Self.isTestHost,
           !LoginItemSettings.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent) {
            model.showWindow()
        }
        startup = Task {
            await model.start()
            if let id = pendingMemoID { pendingMemoID = nil; await model.open(id) }
            spotlight?.refresh()
        }
        if !Self.isTestHost {
            KeyboardShortcuts.onKeyDown(for: .toggleWindow) { [model] in model.toggleWindow() }
            KeyboardShortcuts.onKeyDown(for: .newMemo) { [model] in Task { await model.newMemo() } }
        }
    }

    /// memos://memo/<id> opens a memo.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.host() == "memo", let id = UUID(uuidString: url.lastPathComponent) {
                openMemo(id)
            } else {
                model.showWindow()
            }
        }
    }

    private func openMemo(_ id: UUID) {
        guard let startup else { pendingMemoID = id; return }
        Task {
            await startup.value
            await model.open(id)
        }
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let id = UUID(uuidString: identifier) else { return false }
        openMemo(id)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) { spotlight?.refresh() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Self.isTestHost { try? FileManager.default.removeItem(at: Self.testHostFolder) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            sender.reply(toApplicationShouldTerminate: await model.flush())
        }
        return .terminateLater
    }
}
