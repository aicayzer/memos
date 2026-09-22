import AppIntents
import Foundation

/// A memo as Shortcuts and Spotlight pass it around.
struct MemoEntity: AppEntity {
    let id: UUID

    @Property(title: "Title") var title: String
    @Property(title: "Text") var snippet: String

    init(_ memo: Memo) {
        id = memo.id
        title = memo.title
        snippet = Self.snippet(of: memo)
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Memo")
    static let defaultQuery = MemoQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(snippet)")
    }

    /// What the memo says under its title, cut to a line's worth.
    private static func snippet(of memo: Memo) -> String {
        let title = memo.title
        let body = memo.markdown
            .split(whereSeparator: \.isNewline)
            .map { Memo.title(for: String($0)) }
            .filter { !$0.isEmpty && $0 != title && $0 != Memo.untitled }
            .joined(separator: " ")
        return body.count > 120 ? String(body.prefix(120)) + "…" : body
    }
}

struct MemoQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [MemoEntity] {
        let memos = try await MemoIntents.store().list(matching: nil)
        return memos.filter { identifiers.contains($0.id) }.map(MemoEntity.init)
    }

    func entities(matching string: String) async throws -> [MemoEntity] {
        try await MemoIntents.store().list(matching: string).map(MemoEntity.init)
    }

    func suggestedEntities() async throws -> [MemoEntity] {
        try await MemoIntents.store().list(matching: nil).prefix(20).map(MemoEntity.init)
    }
}

/// The store the intents work through: the same file under the same lock the app and the tool use, so an
/// intent works whether or not the window is open, and the app picks the change up.
enum MemoIntents {
    static func store() throws -> LibraryStore {
        try LibraryStore.inApplicationSupport()
    }

    static func memo(_ entity: MemoEntity, in store: LibraryStore) async throws -> Memo {
        guard let memo = try await store.get(entity.id) else { throw MemoStoreError.missing(entity.id) }
        return memo
    }
}
