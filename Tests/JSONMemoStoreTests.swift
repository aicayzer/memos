import Foundation
import Testing
@testable import Memos

@Suite struct JSONMemoStoreTests {
    private func makeStore() -> (JSONMemoStore, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "memos-\(UUID().uuidString).json")
        return (JSONMemoStore(fileURL: url), url)
    }

    @Test func createsListsAndReadsBack() async throws {
        let (store, url) = makeStore()
        let first = try await store.create(markdown: "First\n")
        try await Task.sleep(for: .milliseconds(2))
        let second = try await store.create(markdown: "Second\n")
        let listed = try await store.list(matching: nil).map(\.id)
        #expect(listed == [second.id, first.id])

        let reopened = JSONMemoStore(fileURL: url)
        let again = try await reopened.get(first.id)
        #expect(again?.markdown == "First\n")
    }

    @Test func updatingMovesAMemoToTheTop() async throws {
        let (store, _) = makeStore()
        let first = try await store.create(markdown: "First\n")
        _ = try await store.create(markdown: "Second\n")
        // The file keeps milliseconds, so two writes in one would tie.
        try await Task.sleep(for: .milliseconds(2))
        _ = try await store.update(first.id, markdown: "First again\n")
        let listed = try await store.list(matching: nil)
        #expect(listed.first?.id == first.id)
        #expect(listed.first?.markdown == "First again\n")
    }

    @Test func favoriteSurvivesReopening() async throws {
        let (store, url) = makeStore()
        let memo = try await store.create(markdown: "Keep\n")
        _ = try await store.setFavorite(memo.id, true)
        let reopened = JSONMemoStore(fileURL: url)
        #expect(try await reopened.get(memo.id)?.favorite == true)
    }

    @Test func favoritesSortFirst() async throws {
        let (store, _) = makeStore()
        let old = try await store.create(markdown: "Old\n")
        _ = try await store.create(markdown: "New\n")
        _ = try await store.setFavorite(old.id, true)
        let listed = try await store.list(matching: nil)
        #expect(listed.first?.id == old.id)
    }

    @Test func queryMatchesTitleAndBodyIgnoringCase() async throws {
        let (store, _) = makeStore()
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
        let (store, _) = makeStore()
        let memo = try await store.create(markdown: "Gone\n")
        try await store.delete(memo.id)
        let listed = try await store.list(matching: nil)
        #expect(listed.isEmpty)
    }

    @Test func updatingAMissingMemoThrows() async throws {
        let (store, _) = makeStore()
        await #expect(throws: MemoStoreError.self) {
            try await store.update(UUID(), markdown: "")
        }
    }
}

@Suite struct JSONMemoStoreFileTests {
    @Test func aMissingFileStartsEmpty() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).json")
        let store = JSONMemoStore(fileURL: url)
        let listed = try await store.list(matching: nil)
        #expect(listed.isEmpty)
    }

    @Test func wholeSecondDatesStillRead() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "seconds-\(UUID().uuidString).json")
        let json = """
        {"memos": [{"id": "6A3F2C8E-0000-4000-8000-000000000001", "markdown": "Old\\n", "pinned": false,
                    "createdAt": "2026-09-21T00:06:11Z", "updatedAt": "2026-09-21T00:06:11Z"}]}
        """
        try Data(json.utf8).write(to: url)
        let listed = try await JSONMemoStore(fileURL: url).list(matching: nil)
        #expect(listed.first?.updatedAt == Date(timeIntervalSince1970: 1_789_949_171))
    }

    @Test func anUnreadableFileIsSetAsideNotOverwritten() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "broken-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)
        let store = JSONMemoStore(fileURL: url)
        _ = try await store.create(markdown: "New\n")
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        let setAside = siblings.filter { $0.hasPrefix(url.lastPathComponent + ".unreadable-") }
        #expect(setAside.count == 1)
        let rewritten = try String(contentsOf: url, encoding: .utf8)
        #expect(rewritten.contains("New"))
    }
}

@Suite struct JSONMemoStoreSharingTests {
    /// Two stores on one file stand in for the app and the command line tool.
    @Test func aChangeByOneIsSeenByTheOther() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "shared-\(UUID().uuidString).json")
        let app = JSONMemoStore(fileURL: url)
        let tool = JSONMemoStore(fileURL: url)
        let first = try await app.create(markdown: "From the app\n")
        try await Task.sleep(for: .milliseconds(2))
        let second = try await tool.create(markdown: "From the tool\n")
        #expect(try await app.list(matching: nil).map(\.id) == [second.id, first.id])
        _ = try await tool.update(first.id, markdown: "Changed by the tool\n")
        #expect(try await app.get(first.id)?.markdown == "Changed by the tool\n")
    }

    @Test func writesFromManyTasksAllLand() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "busy-\(UUID().uuidString).json")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    _ = try await JSONMemoStore(fileURL: url).create(markdown: "Memo \(index)\n")
                }
            }
            try await group.waitForAll()
        }
        #expect(try await JSONMemoStore(fileURL: url).list(matching: nil).count == 20)
    }
}

@Suite struct JSONMemoStoreDateTests {
    @Test func whatIsHandedBackIsWhatTheFileHolds() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "dates-\(UUID().uuidString).json")
        let store = JSONMemoStore(fileURL: url)
        let created = try await store.create(markdown: "Now\n")
        #expect(try await store.get(created.id) == created)
        let updated = try await store.update(created.id, markdown: "Later\n")
        #expect(try await store.get(created.id) == updated)
    }

    @Test func tiesOrderTheSameWayEveryTime() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ties-\(UUID().uuidString).json")
        let store = JSONMemoStore(fileURL: url)
        for index in 0..<8 { _ = try await store.create(markdown: "Memo \(index)\n") }
        let first = try await store.list(matching: nil).map(\.id)
        for _ in 0..<5 {
            #expect(try await JSONMemoStore(fileURL: url).list(matching: nil).map(\.id) == first)
        }
    }
}
