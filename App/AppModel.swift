import AppKit
import Observation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "memos", category: "app")

@MainActor
@Observable
final class AppModel {
    let editor = EditorController()
    let store: any MemoStore

    private(set) var current: Memo?
    private(set) var history = History()

    var title: String { current?.title ?? Memo.untitled }

    @ObservationIgnored private var unsaved: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let lastMemoKey = "lastMemoID"

    init(store: any MemoStore) {
        self.store = store
        editor.onChanged = { [weak self] markdown in self?.changed(markdown) }
        editor.onOpenLink = { NSWorkspace.shared.open($0) }
    }

    func start() async {
        do {
            let memos = try await store.list(matching: nil)
            let last = UserDefaults.standard.string(forKey: Self.lastMemoKey).flatMap(UUID.init(uuidString:))
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

    func open(_ id: Memo.ID) async {
        guard id != current?.id else { return }
        await flush()
        do {
            guard let memo = try await store.get(id) else { return }
            show(memo)
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

    func goBack() async {
        guard let id = history.back() else { return }
        await open(id, recording: false)
    }

    func goForward() async {
        guard let id = history.forward() else { return }
        await open(id, recording: false)
    }

    /// Writes any unsaved edit now. Called before switching memo, on window close and on quit.
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        await save()
    }

    private func open(_ id: Memo.ID, recording: Bool) async {
        if recording { await open(id); return }
        await flush()
        do {
            guard let memo = try await store.get(id) else { return }
            show(memo, recording: false)
        } catch {
            report(error)
        }
    }

    private func show(_ memo: Memo, recording: Bool = true) {
        current = memo
        unsaved = nil
        if recording { history.push(memo.id) }
        UserDefaults.standard.set(memo.id.uuidString, forKey: Self.lastMemoKey)
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

    private func save() async {
        guard let id = current?.id, let markdown = unsaved else { return }
        unsaved = nil
        do {
            let saved = try await store.update(id, markdown: markdown)
            if current?.id == id { current?.updatedAt = saved.updatedAt }
        } catch {
            unsaved = markdown
            report(error)
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
