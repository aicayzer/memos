import CoreSpotlight
import Foundation
import Testing
@testable import Memos

@MainActor
private final class FakeSearchIndex: MemoSearchIndex {
    var memos: [UUID: Memo] = [:]
    var resets = 0
    var updates = 0
    var failUpdate = false
    var duringUpdate: (() async -> Void)?

    func reset() { resets += 1; memos = [:] }
    func update(_ memos: [Memo]) async throws {
        if failUpdate { throw CocoaError(.fileWriteUnknown) }
        updates += 1
        for memo in memos { self.memos[memo.id] = memo }
        if let duringUpdate { self.duringUpdate = nil; await duringUpdate() }
    }
    func remove(_ identifiers: [String]) {
        for identifier in identifiers { if let id = UUID(uuidString: identifier) { memos[id] = nil } }
    }
}

@MainActor
@Suite struct SpotlightTests {
    @Test func indexesExistingMemosAndReconcilesEditsAndDeletions() async throws {
        let store = ChangeableStore([])
        let original = await store.create(markdown: "Original")
        let deleted = await store.create(markdown: "Delete me")
        let index = FakeSearchIndex()
        let subject = SpotlightIndexer(store: store, index: index)
        await subject.refresh().value
        #expect(index.memos.count == 2)
        _ = try await store.update(original.id, markdown: "Changed")
        await store.delete(deleted.id)
        let added = await store.create(markdown: "Added")
        await subject.refresh().value
        #expect(index.memos[original.id]?.markdown == "Changed")
        #expect(index.memos[deleted.id] == nil)
        #expect(index.memos[added.id] == added)
        #expect(index.resets == 1)
        let updates = index.updates
        await subject.refresh().value
        #expect(index.updates == updates)
    }

    @Test func rebuildReplacesStaleResults() async {
        let store = ChangeableStore([])
        let memo = await store.create(markdown: "Current")
        let index = FakeSearchIndex()
        let stale = Memo(id: UUID(), markdown: "Stale", favorite: false, createdAt: .now, updatedAt: .now)
        index.memos[stale.id] = stale
        let subject = SpotlightIndexer(store: store, index: index)
        await subject.refresh().value
        #expect(index.memos == [memo.id: memo])
        index.memos = [:]
        await subject.refresh(rebuild: true).value
        #expect(index.memos == [memo.id: memo])
    }

    @Test func retriesAfterIndexFailure() async {
        let store = ChangeableStore([])
        let memo = await store.create(markdown: "Keep me")
        let index = FakeSearchIndex()
        index.failUpdate = true
        var error: String?
        let subject = SpotlightIndexer(store: store, index: index) { error = $0 }
        await subject.refresh().value
        #expect(error != nil)
        index.failUpdate = false
        await subject.refresh().value
        #expect(error == nil)
        #expect(index.memos[memo.id] == memo)
    }

    @Test func changeDuringIndexingIsNotLost() async throws {
        let store = ChangeableStore([])
        let memo = await store.create(markdown: "Before")
        let index = FakeSearchIndex()
        let subject = SpotlightIndexer(store: store, index: index)
        index.duringUpdate = {
            await store.replace(memo.id, with: "After")
            subject.refresh()
        }
        await subject.refresh().value
        #expect(index.memos[memo.id]?.markdown == "After")
    }

    @Test func searchableContentKeepsIdentityAndOmitsFrontmatter() {
        let memo = Memo(id: UUID(), markdown: "---\nsecret: metadata\n---\n# A title\n\nSearchable body", favorite: false,
                        createdAt: Date(timeIntervalSince1970: 123), updatedAt: Date(timeIntervalSince1970: 456))
        let item = SystemMemoSearchIndex.item(for: memo, domain: "test")
        #expect(item.uniqueIdentifier == memo.id.uuidString)
        #expect(item.attributeSet.title == "A title")
        #expect(item.attributeSet.textContent == "# A title\n\nSearchable body")
        #expect(item.attributeSet.contentCreationDate == memo.createdAt)
        #expect(item.attributeSet.contentModificationDate == memo.updatedAt)
    }
}
