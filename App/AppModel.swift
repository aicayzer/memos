import AppKit
import Observation
import OSLog
import SwiftUI
import UniformTypeIdentifiers
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

    /// Open and closed within a session; each launch starts from the setting.
    var sidePane: Bool

    var sidePaneAtLaunch: Bool {
        didSet { defaults.set(sidePaneAtLaunch, forKey: Self.sidePaneAtLaunchKey) }
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

    /// The Dock change waits for the app to go inactive; see `applyActivationPolicy`.
    private(set) var policyPending = false

    /// 1 is the window color alone, 0 is glass alone.
    var windowOpacity: Double {
        didSet { defaults.set(windowOpacity, forKey: Self.windowOpacityKey) }
    }

    /// The window color over the glass; nil is black or white by appearance.
    var windowTint: NSColor? {
        didSet { defaults.set(windowTint?.hexString, forKey: Self.windowTintKey) }
    }

    var accent: Accent {
        didSet {
            defaults.set(accent.stored, forKey: Self.accentKey)
            editor.accentOverride = accent.color
        }
    }

    var accentColor: Color { accent.color.map(Color.init(nsColor:)) ?? .accentColor }

    var title: String { current?.title ?? Memo.untitled }

    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored private let chrome = WindowChrome()
    @ObservationIgnored private var windowBehavior: NSWindow.CollectionBehavior = []
    @ObservationIgnored private var unsaved: String?
    @ObservationIgnored private var sharePicker: NSSharingServicePicker?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let defaultWindowOpacity = 0.6

    private static let lastMemoKey = "lastMemoID"
    private static let floatingKey = "floating"
    private static let formatBarHiddenKey = "formatBarHidden"
    private static let sidePaneAtLaunchKey = "sidePaneAtLaunch"
    /// Whether the autosaved frame has room for the pane.
    private static let paneRoomKey = "paneRoom"
    private static let menuBarItemKey = "menuBarItem"
    private static let showInDockKey = "showInDock"
    private static let windowOpacityKey = "windowOpacity"
    private static let windowTintKey = "windowTint"
    private static let accentKey = "accent"

    init(store: any MemoStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        floating = defaults.object(forKey: Self.floatingKey) as? Bool ?? true
        formatBarHidden = defaults.bool(forKey: Self.formatBarHiddenKey)
        let paneAtLaunch = defaults.bool(forKey: Self.sidePaneAtLaunchKey)
        sidePaneAtLaunch = paneAtLaunch
        sidePane = paneAtLaunch
        menuBarItem = defaults.bool(forKey: Self.menuBarItemKey)
        showInDock = defaults.object(forKey: Self.showInDockKey) as? Bool ?? true
        windowOpacity = defaults.object(forKey: Self.windowOpacityKey) as? Double ?? Self.defaultWindowOpacity
        windowTint = defaults.string(forKey: Self.windowTintKey).flatMap(NSColor.init(hexString:))
        accent = Accent(stored: defaults.string(forKey: Self.accentKey))
        editor.accentOverride = accent.color
        editor.onChanged = { [weak self] markdown in self?.changed(markdown) }
        editor.onOpenLink = { NSWorkspace.shared.open($0) }
        editor.onCopy = { Self.copy($0) }
    }

    /// Shared files wait here for the service that took them; a sandboxed app's temporary items are not purged
    /// by the system, so the folder is cleared at the next launch, when no transfer can still be reading it.
    private static let shareFolder = FileManager.default.temporaryDirectory.appending(path: "Share")

    func start() async {
        guard current == nil else { return }
        try? FileManager.default.removeItem(at: Self.shareFolder)
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

    func toggleFavorite() async {
        guard let current else { return }
        do {
            self.current = try await store.setFavorite(current.id, !current.favorite)
        } catch {
            report(error)
        }
    }

    func copyAsMarkdown() {
        guard let current else { return }
        Self.copy(current.markdown)
    }

    func saveAs() async {
        showWindowIfHidden()
        await flush()
        guard let current, let window else { return }
        // Sheets and pickers are ordinary windows: only an active app gets their keyboard.
        NSApp.activate()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = Memo.fileName(for: current.title)
        panel.canCreateDirectories = true
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        do {
            try current.markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            report(error)
        }
    }

    /// Shares the memo as a markdown file, from a picker hanging under the title.
    func share() async {
        showWindowIfHidden()
        await flush()
        guard let current, let contentView = window?.contentView else { return }
        do {
            // Its own folder, so the file carries the title as its name.
            let folder = Self.shareFolder.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: Memo.fileName(for: current.title))
            try current.markdown.write(to: url, atomically: true, encoding: .utf8)
            let picker = NSSharingServicePicker(items: [url])
            sharePicker = picker
            NSApp.activate()
            // The hosting view is flipped, so the top row is the first row-height from y = 0.
            let left = sidePane ? Chrome.paneRoom : 0
            let bounds = contentView.bounds
            let top = contentView.isFlipped ? bounds.minY : bounds.maxY - Chrome.rowHeight
            let anchor = NSRect(x: (left + bounds.maxX) / 2 - 1, y: top, width: 2, height: Chrome.rowHeight)
            picker.show(relativeTo: anchor, of: contentView, preferredEdge: contentView.isFlipped ? .maxY : .minY)
        } catch {
            report(error)
        }
    }

    private static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func resetBackground() {
        windowOpacity = Self.defaultWindowOpacity
        windowTint = nil
    }

    func toggleSidePane() {
        showWindowIfHidden()
        // The frame first: a window narrower than its content is widened to the right, and setFrame is
        // not held to the minimum, so closing can shrink it before the content lets the minimum down.
        resizeWindow(forPane: !sidePane)
        sidePane.toggle()
        // Closing takes the search field with it; typing should land in the memo again.
        if !sidePane { editor.focus() }
    }

    /// The pane takes its room on the left, so the memo stays where it is, and gives it back on closing.
    private func resizeWindow(forPane open: Bool) {
        guard let window else { return }
        let delta = open ? Chrome.paneRoom : -Chrome.paneRoom
        var frame = window.frame
        frame.origin.x -= delta
        frame.size.width += delta
        // Against the screen edge, what does not fit on the left goes on the right.
        if let screen = window.screen {
            frame.origin.x = max(frame.origin.x, min(window.frame.minX, screen.visibleFrame.minX))
        }
        window.setFrame(frame, display: true)
        defaults.set(open, forKey: Self.paneRoomKey)
    }

    /// The list as browse and the side pane show it; a failure logs and shows nothing rather than stale rows.
    func memos(matching query: String) async -> [Memo] {
        do {
            return try await store.list(matching: query)
        } catch {
            log.error("list: \(error.localizedDescription, privacy: .public)")
            return []
        }
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
        windowBehavior = window.collectionBehavior
        chrome.attach(window)
        applyWindowLevel()
        // The frame was saved with the pane as it was then, which the launch setting may not match.
        if defaults.bool(forKey: Self.paneRoomKey) != sidePane { resizeWindow(forPane: sidePane) }
    }

    /// Without a Dock icon the app is an accessory: no menu bar, though its key equivalents still work.
    /// Changing the policy while active hands focus to another app and the system refuses to give it back,
    /// so a change made in Settings waits until the app is inactive anyway.
    func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else {
            policyPending = false
            return
        }
        if NSApp.isActive {
            policyPending = true
            return
        }
        NSApp.setActivationPolicy(policy)
        policyPending = false
    }

    /// Key without activating: the app in front keeps the menu bar, this panel takes the keyboard.
    func showWindow() {
        guard let window else { return }
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        editor.focus()
    }

    /// When the app is the one in front, hiding it hands focus back to the previous app; otherwise the panel alone goes.
    func toggleWindow() {
        if let window, window.isKeyWindow, window.isVisible {
            if NSApp.isActive { NSApp.hide(nil) } else { window.orderOut(nil) }
        } else {
            showWindow()
        }
    }

    /// A visible panel under another app's focus needs the keyboard back as much as a closed one needs showing.
    private func showWindowIfHidden() {
        if window?.isKeyWindow != true { showWindow() }
    }

    private func applyWindowLevel() {
        guard let window else { return }
        window.level = floating ? .floating : .normal
        // On top means on every space too, including over full-screen apps; the flags the panel starts with stay.
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
        // An alert from an inactive app lands behind the app in front.
        NSApp.activate()
        NSApp.presentError(error)
    }
}

enum Accent: Equatable {
    case standard
    case system
    case custom(NSColor)

    static let standardColor = NSColor(hexString: "#FFD60A")!

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
