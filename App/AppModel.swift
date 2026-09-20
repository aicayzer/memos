import AppKit
import Observation
import OSLog
import SwiftUI
import WebKit

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app")

@MainActor
@Observable
final class AppModel {
    let editor = EditorController()
    let store: any MemoStore
    private let defaults: UserDefaults

    private(set) var current: Memo?
    private(set) var history = History()
    var overlay: Overlay?
    var findText = ""

    var floating: Bool {
        didSet {
            defaults.set(floating, forKey: Self.floatingKey)
            applyWindowLevel()
        }
    }

    var formatBarHidden: Bool {
        didSet { defaults.set(formatBarHidden, forKey: Self.formatBarHiddenKey) }
    }

    var menuBarItem: Bool {
        didSet { defaults.set(menuBarItem, forKey: Self.menuBarItemKey) }
    }

    var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: Self.showInDockKey)
            applyActivationPolicy()
        }
    }

    /// 1 is the plain window background, 0 is glass alone.
    var windowOpacity: Double {
        didSet { defaults.set(windowOpacity, forKey: Self.windowOpacityKey) }
    }

    var accent: Accent {
        didSet {
            defaults.set(accent.stored, forKey: Self.accentKey)
            editor.accentOverride = accent.color
        }
    }

    var accentColor: Color { accent.color.map(Color.init(nsColor:)) ?? .accentColor }

    var title: String { current?.title ?? Memo.untitled }

    /// Set by the main view, so the window can be reopened after it was closed.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored private let chrome = WindowChrome()
    @ObservationIgnored private var windowBehavior: NSWindow.CollectionBehavior = []
    @ObservationIgnored private var unsaved: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let lastMemoKey = "lastMemoID"
    private static let floatingKey = "floating"
    private static let formatBarHiddenKey = "formatBarHidden"
    private static let menuBarItemKey = "menuBarItem"
    private static let showInDockKey = "showInDock"
    private static let windowOpacityKey = "windowOpacity"
    private static let accentKey = "accent"

    init(store: any MemoStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        floating = defaults.object(forKey: Self.floatingKey) as? Bool ?? true
        formatBarHidden = defaults.bool(forKey: Self.formatBarHiddenKey)
        menuBarItem = defaults.bool(forKey: Self.menuBarItemKey)
        showInDock = defaults.object(forKey: Self.showInDockKey) as? Bool ?? true
        windowOpacity = defaults.object(forKey: Self.windowOpacityKey) as? Double ?? 0.6
        accent = Accent(stored: defaults.string(forKey: Self.accentKey))
        editor.accentOverride = accent.color
        editor.onChanged = { [weak self] markdown in self?.changed(markdown) }
        editor.onOpenLink = { NSWorkspace.shared.open($0) }
        editor.onCopy = { Self.copy($0) }
    }

    func start() async {
        guard current == nil else { return }
        do {
            let memos = try await store.list(matching: nil)
            let last = defaults.string(forKey: Self.lastMemoKey).flatMap(UUID.init(uuidString:))
            if let last, let memo = memos.first(where: { $0.id == last }) {
                show(memo)
            } else if let memo = memos.first {
                show(memo)
            } else {
                show(try await store.create(markdown: ""))
            }
        } catch {
            report(error)
        }
    }

    func open(_ id: Memo.ID, recording: Bool = true) async {
        showWindowIfHidden()
        guard id != current?.id else { return }
        await flush()
        do {
            guard let memo = try await store.get(id) else { return }
            show(memo, recording: recording)
        } catch {
            report(error)
        }
    }

    func newMemo() async {
        showWindowIfHidden()
        await flush()
        do {
            show(try await store.create(markdown: ""))
        } catch {
            report(error)
        }
    }

    func duplicate() async {
        guard let current else { return }
        showWindowIfHidden()
        await flush()
        do {
            show(try await store.create(markdown: current.markdown))
        } catch {
            report(error)
        }
    }

    func togglePin() async {
        guard let current else { return }
        do {
            self.current = try await store.setPinned(current.id, !current.pinned)
        } catch {
            report(error)
        }
    }

    func copyAsMarkdown() {
        guard let current else { return }
        Self.copy(current.markdown)
    }

    private static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func toggle(_ overlay: Overlay) {
        showWindowIfHidden()
        if self.overlay == overlay { dismissOverlay() } else { self.overlay = overlay }
    }

    func dismissOverlay() {
        overlay = nil
        editor.focus()
    }

    func find() {
        guard !findText.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.wraps = true
        editor.webView.find(findText, configuration: configuration) { _ in }
    }

    func attach(_ window: NSWindow) {
        self.window = window
        window.setFrameAutosaveName("main")
        windowBehavior = window.collectionBehavior
        chrome.attach(window)
        applyWindowLevel()
    }

    /// Without a Dock icon the app is an accessory: no menu bar, though its key equivalents still work.
    func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // The change drops the app's active state; the window would otherwise go behind.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func showWindow() {
        NSApp.activate()
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        editor.focus()
    }

    /// Hides the app rather than the window, so focus returns to the previous app.
    func toggleWindow() {
        if NSApp.isActive, let window, window.isKeyWindow, window.isVisible {
            NSApp.hide(nil)
        } else {
            showWindow()
        }
    }

    private func showWindowIfHidden() {
        if window?.isVisible != true { openMainWindow?() }
    }

    private func applyWindowLevel() {
        guard let window else { return }
        window.level = floating ? .floating : .normal
        // On top means on every space too, including over full-screen apps; the flags SwiftUI set stay.
        var behavior = windowBehavior
        if floating {
            behavior.remove(.fullScreenPrimary)
            behavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
        window.collectionBehavior = behavior
    }

    func goBack() async {
        guard let id = history.back() else { return }
        await open(id, recording: false)
    }

    func goForward() async {
        guard let id = history.forward() else { return }
        await open(id, recording: false)
    }

    @discardableResult
    func flush() async -> Bool {
        saveTask?.cancel()
        await saveTask?.value
        saveTask = nil
        if let current, let live = await editor.markdown(), live != current.markdown {
            unsaved = live
            self.current?.markdown = live
        }
        return await save()
    }

    private func show(_ memo: Memo, recording: Bool = true) {
        current = memo
        unsaved = nil
        if recording { history.push(memo.id) }
        defaults.set(memo.id.uuidString, forKey: Self.lastMemoKey)
        editor.load(memo.markdown)
    }

    private func changed(_ markdown: String) {
        guard let current, markdown != current.markdown else { return }
        unsaved = markdown
        self.current?.markdown = markdown
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    @discardableResult
    private func save() async -> Bool {
        guard let id = current?.id, let markdown = unsaved else { return true }
        unsaved = nil
        do {
            let saved = try await store.update(id, markdown: markdown)
            if current?.id == id { current?.updatedAt = saved.updatedAt }
            return true
        } catch {
            if unsaved == nil { unsaved = markdown }
            report(error)
            return false
        }
    }

    private func report(_ error: any Error) {
        log.error("\(error.localizedDescription, privacy: .public)")
        NSApp.presentError(error)
    }
}

enum Accent: Equatable {
    case standard
    case system
    case custom(NSColor)

    static let standardColor = NSColor(srgbRed: 1.0, green: 0.388, blue: 0.388, alpha: 1)

    init(stored: String?) {
        switch stored {
        case nil: self = .standard
        case "system": self = .system
        case let hex?: self = NSColor(hexString: hex).map(Accent.custom) ?? .standard
        }
    }

    var stored: String? {
        switch self {
        case .standard: nil
        case .system: "system"
        case .custom(let color): color.hexString
        }
    }

    /// nil follows the system accent.
    var color: NSColor? {
        switch self {
        case .standard: Self.standardColor
        case .system: nil
        case .custom(let color): color
        }
    }
}

struct History: Equatable {
    private var ids: [Memo.ID] = []
    private var index = -1
    private let limit = 50

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < ids.count - 1 }

    mutating func push(_ id: Memo.ID) {
        if index >= 0, ids[index] == id { return }
        ids.removeSubrange((index + 1)...)
        ids.append(id)
        if ids.count > limit { ids.removeFirst(ids.count - limit) }
        index = ids.count - 1
    }

    mutating func back() -> Memo.ID? {
        guard canGoBack else { return nil }
        index -= 1
        return ids[index]
    }

    mutating func forward() -> Memo.ID? {
        guard canGoForward else { return nil }
        index += 1
        return ids[index]
    }
}
