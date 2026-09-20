import Foundation
import Testing
@testable import Memos

@Suite struct JSONMemoStoreTests {
    private func makeStore() throws -> (JSONMemoStore, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "memos-\(UUID().uuidString).json")
        return (try JSONMemoStore(fileURL: url), url)
    }

    @Test func createsListsAndReadsBack() async throws {
        let (store, url) = try makeStore()
        let first = try await store.create(markdown: "First\n")
        let second = try await store.create(markdown: "Second\n")
        let listed = try await store.list(matching: nil).map(\.id)
        #expect(listed == [second.id, first.id])

        let reopened = try JSONMemoStore(fileURL: url)
        let again = try await reopened.get(first.id)
        #expect(again?.markdown == "First\n")
    }

    @Test func updatingMovesAMemoToTheTop() async throws {
        let (store, _) = try makeStore()
        let first = try await store.create(markdown: "First\n")
        _ = try await store.create(markdown: "Second\n")
        _ = try await store.update(first.id, markdown: "First again\n")
        let listed = try await store.list(matching: nil)
        #expect(listed.first?.id == first.id)
        #expect(listed.first?.markdown == "First again\n")
    }

    @Test func pinnedMemosSortFirst() async throws {
        let (store, _) = try makeStore()
        let old = try await store.create(markdown: "Old\n")
        _ = try await store.create(markdown: "New\n")
        _ = try await store.setPinned(old.id, true)
        let listed = try await store.list(matching: nil)
        #expect(listed.first?.id == old.id)
    }

    @Test func queryMatchesTitleAndBodyIgnoringCase() async throws {
        let (store, _) = try makeStore()
        let groceries = try await store.create(markdown: "Groceries\n\n- Milk\n")
        _ = try await store.create(markdown: "Plan\n\n- call the bank\n")
        let byTitle = try await store.list(matching: "grocer").map(\.id)
        let byBody = try await store.list(matching: "MILK").map(\.id)
        let none = try await store.list(matching: "cheese")
        #expect(byTitle == [groceries.id])
        #expect(byBody == [groceries.id])
        #expect(none.isEmpty)
    }

    @Test func deleteRemovesTheMemo() async throws {
        let (store, _) = try makeStore()
        let memo = try await store.create(markdown: "Gone\n")
        try await store.delete(memo.id)
        let listed = try await store.list(matching: nil)
        #expect(listed.isEmpty)
    }

    @Test func updatingAMissingMemoThrows() async throws {
        let (store, _) = try makeStore()
        await #expect(throws: MemoStoreError.self) {
            try await store.update(UUID(), markdown: "")
        }
    }
}
