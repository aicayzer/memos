import Foundation

protocol MemoStore: Sendable {
    /// Pinned memos first, then most recently updated first. A query matches title and body, case-insensitively.
    func list(matching query: String?) async throws -> [Memo]
    func get(_ id: Memo.ID) async throws -> Memo?
    func create(markdown: String) async throws -> Memo
    func update(_ id: Memo.ID, markdown: String) async throws -> Memo
    func setPinned(_ id: Memo.ID, _ pinned: Bool) async throws -> Memo
    func delete(_ id: Memo.ID) async throws
}

enum MemoStoreError: Error {
    case missing(Memo.ID)
}
