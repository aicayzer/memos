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
    var overlay: Overlay? {
        didSet {
            editor.allowsFocus = overlay == nil
            if overlay != oldValue {
                if overlay != nil { (window as? MemoPanel)?.prepareOverlayFocus() }
                else { (window as? MemoPanel)?.cancelPendingOverlayInput() }
            }
            if oldValue == .find, overlay != .find {
                findText = ""
                editor.find("")
            }
        }
    }
    var findText = ""
    var storageStatus: StorageStatus?
    var convertingStorage = false
    var storageError: String?
    var spotlightError: String?
    var storageNotice: String?
    @ObservationIgnored private var savedMarkdown: String?


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

    private(set) var activationPolicyError: String?

    /// 1 is the window color alone, 0 is glass alone.
    var windowOpacity: Double {
        didSet { defaults.set(windowOpacity, forKey: Self.windowOpacityKey) }
    }

    /// The window color over the glass; nil is black or white by appearance.
    var windowTint: NSColor? {
        didSet { defaults.set(windowTint?.hexString, forKey: Self.windowTintKey) }
    }

    /// Whether the tint and blur below apply; off, the window looks as it does by default.
    var advancedAppearance: Bool {
        didSet { defaults.set(advancedAppearance, forKey: Self.advancedAppearanceKey) }
    }

    /// The glass under the window color; off lets the desktop show through unblurred.
    var windowBlur: Bool {
        didSet { defaults.set(windowBlur, forKey: Self.windowBlurKey) }
    }

    var backdropTint: NSColor? { advancedAppearance ? windowTint : nil }
    var backdropBlur: Bool { !advancedAppearance || windowBlur }

    var appearanceIsDefault: Bool {
        textSize == Self.defaultTextSize && !standardControls && windowOpacity == Self.defaultWindowOpacity
            && !advancedAppearance && windowTint == nil && windowBlur
    }

    func resetAppearance() {
        textSize = Self.defaultTextSize
        standardControls = false
        windowOpacity = Self.defaultWindowOpacity
        advancedAppearance = false
        windowTint = nil
        windowBlur = true
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
    private static let advancedAppearanceKey = "advancedAppearance"
    private static let windowBlurKey = "windowBlur"
    private static let accentKey = "accent"
    private static let textSizeKey = "textSize"
    private static let standardControlsKey = "standardControls"
    private static let menuBarIconKey = "menuBarIcon"

    @ObservationIgnored private let presentError: @MainActor (any Error) -> Void
    @ObservationIgnored private let copyText: @MainActor (String) -> Void

    init(
        store: any MemoStore,
        images: any ImageStore,
        defaults: UserDefaults = .standard,
        editor: (any Editing)? = nil,
        presentError: @escaping @MainActor (any Error) -> Void = { error in
            NSApp.activate()
            NSApp.presentError(error)
        },
        copyText: @escaping @MainActor (String) -> Void = { AppModel.copy($0) }
    ) {
        self.presentError = presentError
        self.copyText = copyText
        self.store = store
        self.images = images
        let editor = editor ?? EditorController(images: images)
        self.editor = editor
        self.defaults = defaults
        shortcuts = ShortcutSettings(defaults: defaults)
        #if DEBUG
        floating = defaults.object(forKey: Self.floatingKey) as? Bool ?? false
        #else
        floating = defaults.object(forKey: Self.floatingKey) as? Bool ?? true
        #endif
        formatBarHidden = defaults.object(forKey: Self.formatBarHiddenKey) as? Bool ?? true
        let paneAtLaunch = defaults.bool(forKey: Self.sidePaneAtLaunchKey)
        sidePaneAtLaunch = paneAtLaunch
        sidePane = paneAtLaunch
        menuBarItem = defaults.bool(forKey: Self.menuBarItemKey)
        showInDock = defaults.object(forKey: Self.showInDockKey) as? Bool ?? true
        windowOpacity = defaults.object(forKey: Self.windowOpacityKey) as? Double ?? Self.defaultWindowOpacity
        let storedTint = defaults.string(forKey: Self.windowTintKey).flatMap(NSColor.init(hexString:))
        windowTint = storedTint
        // A tint chosen before the switch existed keeps applying.
        advancedAppearance = defaults.object(forKey: Self.advancedAppearanceKey) as? Bool ?? (storedTint != nil)
        windowBlur = defaults.object(forKey: Self.windowBlurKey) as? Bool ?? true
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
        editor.onCopy = copyText
        editor.onWarning = { [weak self] message in self?.report(MemoClipboardError.unavailable(message)) }
        editor.onDropFiles = { [weak self] urls, point in
            guard let self else { return }
            Task { await self.dropped(urls, at: point) }
        }

    }

    /// Shared files wait here for the service that took them; a sandboxed app's temporary items are not purged
    /// by the system, so the folder is cleared at the next launch, when no transfer can still be reading it.
    private static let shareFolder = FileManager.default.temporaryDirectory.appending(path: "Share")

    func didConvertStorage() { storeGeneration += 1 }

    func start() async {
        await refreshStorage()
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
        guard id != current?.id else { editor.focus(); return }
        guard !convertingStorage, await flush() else { return }
        do {
            guard let memo = try await store.get(id) else { return }
            show(memo, recording: recording)
        } catch {
            report(error)
        }
    }

    func newMemo() async {
        showWindowIfHidden()
        guard !convertingStorage, await flush() else { return }
        do {
            show(try await store.create(markdown: ""))
        } catch {
            report(error)
        }
    }

    func duplicate() async {
        guard let current else { return }
        showWindowIfHidden()
        guard !convertingStorage, await flush() else { return }
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
        let documentID = current?.id
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
        guard current?.id == documentID else { return }
        if refused { NSSound.beep() }
        if !references.isEmpty { editor.insertImages(references, at: point) }
        if !paths.isEmpty { editor.insertPaths(paths, at: point) }
    }


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
        guard !convertingStorage else { return }
        switch shortcut {
        case .newMemo: Task { await newMemo() }
        case .delete: Task { await deleteMemo() }
        case .duplicate: Task { await duplicate() }
        case .favorite: Task { await toggleFavorite() }
        case .browse: toggle(.browse)
        case .back: Task { await goBack() }
        case .forward: Task { await goForward() }
        case .copyMarkdown: Task { await copyAsMarkdown() }
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

    func table(_ command: String) { editor.table(command) }

    func pasteAsPlainText() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        editor.pasteAsPlainText(text)
    }

    func copyAsMarkdown() async {
        guard let current else { return }
        let id = current.id
        do {
            let text = try await editor.snapshot()
            guard self.current?.id == id else { throw MemoEditorError.documentChanged }
            copyText(text)
        } catch { report(error) }
    }

    func saveAs() async {
        showWindowIfHidden()
        guard await flush() else { return }
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
        guard await flush() else { return }
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
        if self.overlay == overlay {
            dismissOverlay()
        } else {
            self.overlay = overlay
            showWindowIfHidden()
        }
    }

    func dismissOverlay() { dismissOverlay(restoringEditor: true) }

    func dismissOverlay(restoringEditor: Bool) {
        overlay = nil
        if restoringEditor { editor.focus() }
    }

    func find() {
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

    func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { activationPolicyError = nil; return }
        let wasActive = NSApp.isActive
        let applied = NSApp.setActivationPolicy(policy)
        // Cancel the activation yield so changing Dock visibility does not dismiss Settings.
        if applied && wasActive { NSApp.activate() }
        activationPolicyError = applied || NSApp.activationPolicy() == policy
            ? nil : "Could not update Dock visibility. Try changing the setting again."
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
            Task {
                guard await flush() else { return }
                if NSApp.isActive { NSApp.hide(nil) } else { window.orderOut(nil) }
            }
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
        if let current {
            do {
                let live = try await editor.snapshot()
                guard self.current?.id == current.id else { throw MemoEditorError.documentChanged }
                if live != current.markdown {
                    unsaved = live
                    self.current?.markdown = live
                }
            } catch {
                report(error)
                return false
            }
        }
        return await save()
    }

    private func show(_ memo: Memo, recording: Bool = true, keepingCaret: Bool = false) {
        current = memo
        editor.documentID = String(describing: memo.id)
        savedMarkdown = memo.markdown
        unsaved = nil
        if recording { history.push(memo.id) }
        defaults.set(memo.id.uuidString, forKey: Self.lastMemoKey)
        if keepingCaret { editor.reload(memo.markdown) } else { editor.load(memo.markdown) }
    }

    private func changed(_ markdown: String) {
        guard !convertingStorage else { return }
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
        guard !convertingStorage else { return }
        storeChangeTask?.cancel()
        storeChangeTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await refreshStorage()
            storeGeneration += 1
            guard let id = current?.id else { return }
            // Flush against the loaded revision; a conflict keeps both versions before any reload.
            guard await flush() else { return }
            // A write that did not land keeps the text on screen; nothing is read over it.
            guard !Task.isCancelled, current?.id == id, unsaved == nil,
                  let expectedSource = current?.markdown else { return }
            do {
                let fresh = try await store.get(id)
                guard !Task.isCancelled, current?.id == id, unsaved == nil else { return }
                guard let fresh else {
                    // Deleted elsewhere: the memo after it, or a new one.
                    let memo: Memo
                    if let next = try await store.list(matching: nil).first { memo = next } else { memo = try await store.create(markdown: "") }
                    guard !Task.isCancelled, current?.id == id, unsaved == nil else { return }
                    try await refresh(memo, replacing: id, expecting: expectedSource, recording: true)
                    return
                }
                if fresh.markdown != expectedSource {
                    try await refresh(fresh, replacing: id, expecting: expectedSource, recording: false)
                } else {
                    current?.favorite = fresh.favorite
                    current?.updatedAt = fresh.updatedAt
                }
            } catch {
                report(error)
            }
        }
    }

    private func refresh(_ memo: Memo, replacing originalID: Memo.ID, expecting source: String, recording: Bool) async throws {
        let result = try await editor.refresh(memo.markdown, documentID: memo.id.uuidString, expecting: source)
        guard current?.id == originalID else { return }
        switch result {
        case .edited(let live):
            changed(live)
        case .applied:
            let pending = unsaved
            current = memo
            savedMarkdown = memo.markdown
            unsaved = nil
            if recording { history.push(memo.id) }
            defaults.set(memo.id.uuidString, forKey: Self.lastMemoKey)
            if let pending { changed(pending) }
        }
    }

    @discardableResult
    private func save() async -> Bool {
        guard let id = current?.id, let markdown = unsaved else { return true }
        unsaved = nil
        do {
            let saved = try await store.update(id, markdown: markdown, expecting: savedMarkdown)
            if current?.id == id { current?.updatedAt = saved.updatedAt; savedMarkdown = saved.markdown }
            return true
        } catch StorageError.conflict {
            do {
                let recovered = try await store.create(markdown: markdown)
                if current?.id == id {
                    try await adoptRecovery(recovered, replacing: id)
                }
                storageNotice = "This memo changed elsewhere. Your edits are in a separate memo; the external version is unchanged."
                return true
            } catch {
                if unsaved == nil { unsaved = markdown }
                report(error)
                return false
            }
        } catch MemoStoreError.missing {
            // Deleted elsewhere while being written: the text on screen becomes a memo again, in place.
            do {
                let recreated = try await store.create(markdown: markdown)
                if current?.id == id {
                    try await adoptRecovery(recreated, replacing: id)
                    storageNotice = "The original was deleted elsewhere. Your unsaved edits were recovered as a new memo."
                }
                return true
            } catch {
                if unsaved == nil { unsaved = markdown }
                report(error)
                return false
            }
        } catch {
            if unsaved == nil { unsaved = markdown }
            report(error)
            return false
        }
    }

    private func adoptRecovery(_ memo: Memo, replacing originalID: Memo.ID) async throws {
        guard current?.id == originalID else { return }
        let reported = unsaved
        let live = try await editor.rebind(to: String(describing: memo.id))
        guard current?.id == originalID else { return }
        let latest = unsaved != reported ? unsaved ?? live : live
        current = memo
        savedMarkdown = memo.markdown
        unsaved = nil
        history.push(memo.id)
        defaults.set(memo.id.uuidString, forKey: Self.lastMemoKey)
        // Rebinding captures even edits whose change message has not reached the app yet.
        changed(latest)
    }

    private func report(_ error: any Error) {
        log.error("\(error.localizedDescription, privacy: .public)")
        // An alert from an inactive app lands behind the app in front.
        presentError(error)
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
