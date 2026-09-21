import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "store")

/// One JSON file, read and written whole under a lock for every operation, so the app and the command line
/// tool share it: a change by one is on disk for the other's next read, and neither writes over the other's.
/// Nothing is cached; the file is small.
actor JSONMemoStore: MemoStore {
    let fileURL: URL
    /// The data file is replaced on every write, so the lock is a file of its own.
    private let lockURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        lockURL = fileURL.appendingPathExtension("lock")
    }

    static func inApplicationSupport() throws -> JSONMemoStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return JSONMemoStore(fileURL: directory.appending(path: "store.json"))
    }

    func list(matching query: String?) throws -> [Memo] {
        let needle = query?.trimmingCharacters(in: .whitespaces) ?? ""
        return try reading { memos in
            memos.values
                .filter { needle.isEmpty || $0.markdown.localizedCaseInsensitiveContains(needle) }
                .sorted { a, b in
                    if a.favorite != b.favorite { return a.favorite }
                    if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                    return a.createdAt > b.createdAt
                }
        }
    }

    func get(_ id: Memo.ID) throws -> Memo? {
        try reading { $0[id] }
    }

    func create(markdown: String) throws -> Memo {
        try writing { memos in
            let now = Date()
            let memo = Memo(id: UUID(), markdown: markdown, favorite: false, createdAt: now, updatedAt: now)
            memos[memo.id] = memo
            return memo
        }
    }

    func update(_ id: Memo.ID, markdown: String) throws -> Memo {
        try writing { memos in
            guard var memo = memos[id] else { throw MemoStoreError.missing(id) }
            memo.markdown = markdown
            memo.updatedAt = Date()
            memos[id] = memo
            return memo
        }
    }

    func setFavorite(_ id: Memo.ID, _ favorite: Bool) throws -> Memo {
        try writing { memos in
            guard var memo = memos[id] else { throw MemoStoreError.missing(id) }
            memo.favorite = favorite
            memos[id] = memo
            return memo
        }
    }

    func delete(_ id: Memo.ID) throws {
        try writing { memos in memos[id] = nil }
    }

    private func reading<T>(_ body: ([Memo.ID: Memo]) throws -> T) throws -> T {
        try locked(exclusive: false) { try body(try load()) }
    }

    private func writing<T>(_ body: (inout [Memo.ID: Memo]) throws -> T) throws -> T {
        try locked(exclusive: true) {
            var memos = try load()
            let result = try body(&memos)
            let data = try Self.encoder.encode(File(memos: Array(memos.values)))
            try data.write(to: fileURL, options: .atomic)
            return result
        }
    }

    private func locked<T>(exclusive: Bool, _ body: () throws -> T) throws -> T {
        let descriptor = open(lockURL.path, O_RDONLY | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        defer { close(descriptor) }
        guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func load() throws -> [Memo.ID: Memo] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        }
        do {
            let file = try Self.decoder.decode(File.self, from: data)
            return Dictionary(uniqueKeysWithValues: file.memos.map { ($0.id, $0) })
        } catch {
            // An unreadable file is set aside rather than written over by the next save.
            let aside = fileURL.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
            try FileManager.default.moveItem(at: fileURL, to: aside)
            log.error("store file set aside as \(aside.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private struct File: Codable {
        var memos: [Memo]
    }

    // Whole seconds would tie memos made within one, and the order is read back from the file every time.
    private static let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateFormat))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? dateFormat.parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a date: \(text)"))
        }
        return decoder
    }()
}
