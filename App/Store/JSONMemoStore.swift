import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "store")

actor JSONMemoStore: MemoStore {
    private let fileURL: URL
    private var memos: [Memo.ID: Memo] = [:]

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return
        }
        do {
            let file = try Self.decoder.decode(File.self, from: data)
            memos = Dictionary(uniqueKeysWithValues: file.memos.map { ($0.id, $0) })
        } catch {
            // An unreadable file is set aside rather than overwritten by the next save.
            let aside = fileURL.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
            try FileManager.default.moveItem(at: fileURL, to: aside)
            log.error("store file set aside as \(aside.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func inApplicationSupport() throws -> JSONMemoStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try JSONMemoStore(fileURL: directory.appending(path: "store.json"))
    }

    func list(matching query: String?) -> [Memo] {
        let needle = query?.trimmingCharacters(in: .whitespaces) ?? ""
        return memos.values
            .filter { needle.isEmpty || $0.markdown.localizedCaseInsensitiveContains(needle) }
            .sorted { a, b in
                if a.pinned != b.pinned { return a.pinned }
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                return a.createdAt > b.createdAt
            }
    }

    func get(_ id: Memo.ID) -> Memo? {
        memos[id]
    }

    func create(markdown: String) throws -> Memo {
        let now = Date()
        let memo = Memo(id: UUID(), markdown: markdown, pinned: false, createdAt: now, updatedAt: now)
        memos[memo.id] = memo
        try save()
        return memo
    }

    func update(_ id: Memo.ID, markdown: String) throws -> Memo {
        guard var memo = memos[id] else { throw MemoStoreError.missing(id) }
        memo.markdown = markdown
        memo.updatedAt = Date()
        memos[id] = memo
        try save()
        return memo
    }

    func setPinned(_ id: Memo.ID, _ pinned: Bool) throws -> Memo {
        guard var memo = memos[id] else { throw MemoStoreError.missing(id) }
        memo.pinned = pinned
        memos[id] = memo
        try save()
        return memo
    }

    func delete(_ id: Memo.ID) throws {
        memos[id] = nil
        try save()
    }

    private func save() throws {
        let data = try Self.encoder.encode(File(memos: Array(memos.values)))
        try data.write(to: fileURL, options: .atomic)
    }

    private struct File: Codable {
        var memos: [Memo]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
