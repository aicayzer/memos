import Foundation

protocol MemoStore: Sendable {
    /// Favorites first, then most recently updated first. A query matches title and body, case-insensitively.
    func list(matching query: String?) async throws -> [Memo]
    func get(_ id: Memo.ID) async throws -> Memo?
    func create(markdown: String) async throws -> Memo
    func update(_ id: Memo.ID, markdown: String) async throws -> Memo
    func setFavorite(_ id: Memo.ID, _ favorite: Bool) async throws -> Memo
    func delete(_ id: Memo.ID) async throws
}

enum MemoStoreError: LocalizedError {
    case missing(Memo.ID)
    case locked(URL, Int32)

    var errorDescription: String? {
        switch self {
        case .missing(let id): "There is no memo \(id.uuidString.lowercased())."
        case .locked(let url, let code): "The store could not be locked at \(url.path): \(String(cString: strerror(code)))."
        }
    }
}
