@preconcurrency import CoreSpotlight
import OSLog
import UniformTypeIdentifiers

@MainActor
protocol MemoSearchIndex {
    func reset() async throws
    func update(_ memos: [Memo]) async throws
    func remove(_ identifiers: [String]) async throws
}

@MainActor
final class SystemMemoSearchIndex: MemoSearchIndex {
    let index = CSSearchableIndex.default()
    private let domain = Bundle.main.bundleIdentifier! + ".memos"

    static func item(for memo: Memo, domain: String) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = memo.title
        let body = MarkdownDocument.body(of: memo.markdown)
        attributes.contentDescription = String(body.prefix(300))
        attributes.textContent = body
        attributes.contentCreationDate = memo.createdAt
        attributes.contentModificationDate = memo.updatedAt
        let item = CSSearchableItem(uniqueIdentifier: memo.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    func reset() async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
    }

    func update(_ memos: [Memo]) async throws {
        try await index.indexSearchableItems(memos.map { Self.item(for: $0, domain: domain) })
    }

    func remove(_ identifiers: [String]) async throws {
        try await index.deleteSearchableItems(withIdentifiers: identifiers)
    }
}

/// The store stays authoritative. Relaunch rebuilds the index, including changes made while the app was closed.
@MainActor
final class SpotlightIndexer: NSObject, CSSearchableIndexDelegate {
    private let store: any MemoStore
    private let index: any MemoSearchIndex
    private let onError: (String?) -> Void
    private var indexed: [UUID: Memo] = [:]
    private var needsReset = true
    private var needsRefresh = false
    private var task: Task<Void, Never>?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "spotlight")

    init(store: any MemoStore, index: any MemoSearchIndex, onError: @escaping (String?) -> Void = { _ in }) {
        self.store = store
        self.index = index
        self.onError = onError
        super.init()
        (index as? SystemMemoSearchIndex)?.index.indexDelegate = self
    }

    @discardableResult
    func refresh(rebuild: Bool = false) -> Task<Void, Never> {
        needsReset = needsReset || rebuild
        needsRefresh = true
        if let task { return task }
        let task = Task {
            while needsRefresh {
                needsRefresh = false
                do {
                    // Read before resetting: a temporarily inaccessible folder must not erase search results.
                    let memos = try await store.list(matching: nil)
                    if needsReset {
                        needsReset = false
                        try await index.reset()
                        indexed = [:]
                    }
                    let latest = Dictionary(uniqueKeysWithValues: memos.map { ($0.id, $0) })
                    let changed = memos.filter { indexed[$0.id] != $0 }
                    let removed = indexed.keys.filter { latest[$0] == nil }.map(\.uuidString)
                    if !changed.isEmpty { try await index.update(changed) }
                    if !removed.isEmpty { try await index.remove(removed) }
                    indexed = latest
                    onError(nil)
                } catch {
                    needsReset = true
                    log.error("index: \(error.localizedDescription, privacy: .public)")
                    onError("Spotlight could not update: \(error.localizedDescription)")
                    break
                }
            }
            self.task = nil
        }
        self.task = task
        return task
    }

    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping @Sendable () -> Void) {
        Task { @MainActor in
            await refresh(rebuild: true).value
            acknowledgementHandler()
        }
    }

    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping @Sendable () -> Void) {
        Task { @MainActor in
            await refresh(rebuild: true).value
            acknowledgementHandler()
        }
    }
}
