import AppKit
import Observation
import OSLog
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

    var title: String { current?.title ?? Memo.untitled }

    /// Set by the main view, so the window can be reopened after it was closed.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored private var unsaved: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let lastMemoKey = "lastMemoID"
    private static let floatingKey = "floating"
    private static let formatBarHiddenKey = "formatBarHidden"

    init(store: any MemoStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        floating = defaults.object(forKey: Self.floatingKey) as? Bool ?? true
        formatBarHidden = defaults.bool(forKey: Self.formatBarHiddenKey)
        editor.onChanged = { [weak self] markdown in self?.changed(markdown) }
        editor.onOpenLink = { NSWorkspace.shared.open($0) }
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
        await flush()
        do {
            show(try await store.create(markdown: ""))
        } catch {
            report(error)
        }
    }

    func duplicate() async {
        guard let current else { return }
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(current.markdown, forType: .string)
    }

    func toggle(_ overlay: Overlay) {
        if self.overlay == overlay { dismissOverlay() } else { self.overlay = overlay }
    }

    func dismissOverlay() {
        overlay = nil
        editor.focus()
    }

    func find(next: Bool = false) {
        guard !findText.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.wraps = true
        editor.webView.find(findText, configuration: configuration) { _ in }
    }

    func attach(_ window: NSWindow) {
        self.window = window
        applyWindowLevel()
    }

    /// The global hotkey: hide the window when it is in front, otherwise bring it forward.
    func toggleWindow() {
        if NSApp.isActive, let window, window.isKeyWindow, window.isVisible {
            NSApp.hide(nil)
        } else {
            NSApp.activate()
            if let window, window.isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                openMainWindow?()
            }
            editor.focus()
        }
    }

    private func applyWindowLevel() {
        window?.level = floating ? .floating : .normal
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
        if let current, editor.isReady {
            let live = await editor.markdown()
            if live != current.markdown {
                unsaved = live
                self.current?.markdown = live
            }
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
