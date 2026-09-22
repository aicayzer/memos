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
    let editor: any Editing
    let store: any MemoStore
    let images: any ImageStore
    let shortcuts: ShortcutSettings
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

    var menuBarIcon: MenuBarIcon {
        didSet { defaults.set(menuBarIcon.rawValue, forKey: Self.menuBarIconKey) }
    }

    /// The app's own controls at a toolbar's size rather than the window's own, smaller one.
    var standardControls: Bool {
        didSet { defaults.set(standardControls, forKey: Self.standardControlsKey) }
    }

    var chromeMetrics: ChromeMetrics { standardControls ? .standard : .compact }

    /// The memo's text size in points; headings and the rest scale with it.
    var textSize: Double {
        didSet {
            defaults.set(textSize, forKey: Self.textSizeKey)
            editor.textSize = textSize
        }
    }

    var accentColor: Color { accent.color.map(Color.init(nsColor:)) ?? .accentColor }

    var title: String { current?.title ?? Memo.untitled }

    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored private let windowChrome = WindowChrome()
    @ObservationIgnored private var windowBehavior: NSWindow.CollectionBehavior = []
    @ObservationIgnored private var unsaved: String?
    @ObservationIgnored private var sharePicker: NSSharingServicePicker?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var storeChangeTask: Task<Void, Never>?

    /// Counts the store's changes from outside; lists keyed on it read again.
    private(set) var storeGeneration = 0

    static let defaultWindowOpacity = 0.6
    static let defaultTextSize = TextSize.medium.points

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
    private static let textSizeKey = "textSize"
    private static let standardControlsKey = "standardControls"
    private static let menuBarIconKey = "menuBarIcon"

    init(
        store: any MemoStore,
        images: any ImageStore,
        defaults: UserDefaults = .standard,
        editor: (any Editing)? = nil
    ) {
        self.store = store
        self.images = images
        let editor = editor ?? EditorController(images: images)
        self.editor = editor
        self.defaults = defaults
        shortcuts = ShortcutSettings(defaults: defaults)
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
        standardControls = defaults.bool(forKey: Self.standardControlsKey)
        menuBarIcon = defaults.string(forKey: Self.menuBarIconKey).flatMap(MenuBarIcon.init(rawValue:)) ?? .squiggle
        let storedSize = defaults.object(forKey: Self.textSizeKey) as? Double ?? Self.defaultTextSize
        textSize = TextSize(nearest: storedSize).points
        editor.accentOverride = accent.color
        editor.textSize = textSize
        editor.keymap = shortcuts.editorKeymap
        shortcuts.onChange = { [weak self] in
            guard let self else { return }
            self.editor.keymap = shortcuts.editorKeymap
        }
        editor.onChanged = { [weak self] markdown in self?.changed(markdown) }
        editor.onOpenLink = { NSWorkspace.shared.open($0) }
        editor.onCopy = { Self.copy($0) }
        editor.onDropFiles = { [weak self] urls, point in
            guard let self else { return }
            Task { await self.dropped(urls, at: point) }
        }
        editor.onPasteImage = { [weak self] in
            guard let self else { return }
            Task { await self.pasteImage() }
        }
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
        await ImageSweep.run(store: store, images: images, alsoKeeping: [current?.markdown].compactMap(\.self))
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
            // The file's memo may lag an edit that has not saved yet; only the flag is taken from it.
            let saved = try await store.setFavorite(current.id, !current.favorite)
            self.current?.favorite = saved.favorite
            self.current?.updatedAt = saved.updatedAt
        } catch {
            report(error)
        }
    }

    /// Asks first, naming the memo, and then shows what followed it in browse order.
    func deleteMemo() async {
        showWindowIfHidden()
        guard let memo = current, let window else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \u{201C}\(Memo.abbreviated(memo.title, to: 40))\u{201D}?"
        alert.informativeText = "This memo will be deleted permanently."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
        await delete(memo)
    }

    /// The delete itself, once it is agreed.
    func delete(_ memo: Memo) async {
        // Nothing may write this memo again: a save in flight would put it back.
        saveTask?.cancel()
        saveTask = nil
        unsaved = nil
        do {
            let ordered = try await store.list(matching: nil)
            try await store.delete(memo.id)
            history.remove(memo.id)
            let following = ordered.drop(while: { $0.id != memo.id }).dropFirst().first
            if let next = following ?? ordered.first(where: { $0.id != memo.id }) {
                show(next)
            } else {
                show(try await store.create(markdown: ""))
            }
        } catch {
            report(error)
        }
        await ImageSweep.run(store: store, images: images, alsoKeeping: [current?.markdown].compactMap(\.self))
    }

    /// Settings is a SwiftUI scene with no handle the app can hold; its menu item is what opens it, and
    /// the selector behind that is only reachable when the menu bar is there.
    func showSettings() {
        NSApp.activate()
        for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            if let index = menu.items.firstIndex(where: { $0.title.hasPrefix("Settings") }) {
                menu.performActionForItem(at: index)
                return
            }
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Dropped images are kept and shown; anything else still reads as its path.
    private func dropped(_ urls: [URL], at point: CGPoint) async {
        var references: [ImageReference] = []
        var paths: [String] = []
        var refused = false
        for url in urls {
            let data = try? Data(contentsOf: url)
            if let data, let reference = await kept(data, called: url.deletingPathExtension().lastPathComponent) {
                references.append(reference)
            } else if (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true {
                refused = true
            } else {
                // A folder's path as Finder copies it, without the slash a URL carries.
                let path = url.path(percentEncoded: false)
                paths.append(path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path)
            }
        }
        if refused { NSSound.beep() }
        if !references.isEmpty { editor.insertImages(references, at: point) }
        if !paths.isEmpty { editor.insertPaths(paths, at: point) }
    }

    /// The editor says an image was pasted rather than sending its bytes; they are already on the
    /// pasteboard, where the app can read them natively.
    private func pasteImage() async {
        let pasteboard = NSPasteboard.general
        var images: [(Data, String)] = []
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls {
            if let data = try? Data(contentsOf: url) { images.append((data, url.deletingPathExtension().lastPathComponent)) }
        }
        if images.isEmpty {
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = pasteboard.data(forType: type) {
                    images.append((data, ""))
                    break
                }
            }
        }
        var references: [ImageReference] = []
        for (data, name) in images {
            if let reference = await kept(data, called: name) { references.append(reference) }
        }
        guard !references.isEmpty else { return NSSound.beep() }
        editor.insertImages(references, at: nil)
    }

    /// Keeps the bytes as they are when the store takes them, and as a PNG when it does not, so an image
    /// from any app lands in one of the few types a memo holds.
    private func kept(_ data: Data, called name: String) async -> ImageReference? {
        var path: String?
        if let reference = try? await images.save(data) {
            path = reference.path
        } else if let image = NSImage(data: data), let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
                  let reference = try? await images.save(png) {
            path = reference.path
        }
        // A bar in the name would read as a width when the memo is opened again.
        return path.map { ImageReference(path: $0, alt: name.replacing("|", with: " ")) }
    }

    /// Every shortcut's action, for the keys the menu does not carry.
    func perform(_ shortcut: Shortcut) {
        switch shortcut {
        case .newMemo: Task { await newMemo() }
        case .delete: Task { await deleteMemo() }
        case .duplicate: Task { await duplicate() }
        case .favorite: Task { await toggleFavorite() }
        case .browse: toggle(.browse)
        case .back: Task { await goBack() }
        case .forward: Task { await goForward() }
        case .copyMarkdown: copyAsMarkdown()
        case .saveAs: Task { await saveAs() }
        case .find: toggle(.find)
        case .palette: toggle(.palette)
        case .sidePane: toggleSidePane()
        case .heading1: editor.format(.heading, argument: "1")
        case .heading2: editor.format(.heading, argument: "2")
        case .heading3: editor.format(.heading, argument: "3")
        case .paragraph: editor.format(.paragraph)
        case .bold: editor.format(.bold)
        case .italic: editor.format(.italic)
        case .strikethrough: editor.format(.strikethrough)
        case .code: editor.format(.code)
        case .codeBlock: editor.format(.codeBlock)
        case .quote: editor.format(.quote)
        case .bulletList: editor.format(.bulletList)
        case .orderedList: editor.format(.orderedList)
        case .taskList: editor.format(.taskList)
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
            try await copyImages(of: current.markdown, besideFileAt: url)
        } catch {
            report(error)
        }
    }

    /// An export stands alone: the images the memo refers to go into a folder of that name beside it, so
    /// the relative paths in the file still find them.
    private func copyImages(of markdown: String, besideFileAt url: URL) async throws {
        let used = ImageReference.references(in: markdown)
        guard !used.isEmpty else { return }
        let folder = url.deletingLastPathComponent().appending(path: ImageReference.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for path in used {
            guard let source = await images.url(for: path) else { continue }
            let destination = folder.appending(path: source.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try FileManager.default.copyItem(at: source, to: destination)
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

    var isDefaultAppearance: Bool {
        accent == .standard && textSize == Self.defaultTextSize && !standardControls
            && windowOpacity == Self.defaultWindowOpacity && windowTint == nil
    }

    func resetAppearance() {
        accent = .standard
        textSize = Self.defaultTextSize
        standardControls = false
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
        editor.find(findText)
    }

    func attach(_ window: NSWindow) {
        self.window = window
        windowBehavior = window.collectionBehavior
        windowChrome.attach(window)
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

    private func show(_ memo: Memo, recording: Bool = true, keepingCaret: Bool = false) {
        current = memo
        unsaved = nil
        if recording { history.push(memo.id) }
        defaults.set(memo.id.uuidString, forKey: Self.lastMemoKey)
        if keepingCaret { editor.reload(memo.markdown) } else { editor.load(memo.markdown) }
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
            // A later edit's task is the one to keep.
            if !Task.isCancelled { saveTask = nil }
        }
    }

    /// For the tests: a pending store change and save have landed.
    func settle() async {
        await storeChangeTask?.value
        await saveTask?.value
    }

    /// The store's folder changed. The app's own writes land here too, a few events per save, so the look
    /// waits for the burst to end; the memo on screen is reread unless an edit is on its way to the file.
    func storeChanged() {
        storeChangeTask?.cancel()
        storeChangeTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            storeGeneration += 1
            guard let id = current?.id else { return }
            // An edit on its way to the file is the app's answer for this memo: it is written first, and
            // what the store then holds is what the window shows. A write from outside in that moment is
            // the one that loses.
            if unsaved != nil || saveTask != nil { await flush() }
            // A write that did not land keeps the text on screen; nothing is read over it.
            guard !Task.isCancelled, current?.id == id, unsaved == nil else { return }
            do {
                let fresh = try await store.get(id)
                guard !Task.isCancelled, current?.id == id else { return }
                guard let fresh else {
                    // Deleted elsewhere: the memo after it, or a new one.
                    if let memo = try await store.list(matching: nil).first { show(memo) } else { show(try await store.create(markdown: "")) }
                    return
                }
                if fresh.markdown != current?.markdown {
                    show(fresh, recording: false, keepingCaret: true)
                } else {
                    current?.favorite = fresh.favorite
                    current?.updatedAt = fresh.updatedAt
                }
            } catch {
                report(error)
            }
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
        } catch MemoStoreError.missing {
            // Deleted elsewhere while being written: the text on screen becomes a memo again, in place.
            do {
                let recreated = try await store.create(markdown: markdown)
                if current?.id == id {
                    current = recreated
                    defaults.set(recreated.id.uuidString, forKey: Self.lastMemoKey)
                }
                return true
            } catch {
                unsaved = markdown
                report(error)
                return false
            }
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

    /// Also the app's global accent (project.yml), so AppKit draws its own controls in it, the Settings
    /// toolbar's selected tab among them, when the system accent is Multicolor.
    static let standardColor = NSColor(named: "AccentColor")!

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

    /// A deleted memo leaves the stack altogether; the place in it moves back by what went before.
    mutating func remove(_ id: Memo.ID) {
        guard index >= 0 else { return }
        let removedBefore = ids[..<index].count { $0 == id }
        ids.removeAll { $0 == id }
        index = min(index - removedBefore, ids.count - 1)
    }
}
