import CryptoKit
import Foundation
import OSLog

private let storageLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Memos", category: "storage")

enum StorageError: LocalizedError {
    case invalid(String)
    case conflict(URL)
    case changedDuringConversion

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .conflict(let url): "This memo changed elsewhere. Your edit was saved separately in \(url.path). Reload the memo before editing again."
        case .changedDuringConversion: "Files changed during conversion. Your storage setting has not changed. Try again after the other editor finishes saving."
        }
    }
}

struct StorageStatus: Sendable {
    var markdown: Bool
    var location: URL
    var recovery: URL?
}

/// Every operation rereads the committed location under one process-shared lock. Conversion builds an
/// independent generation, then commits one pointer; a crash cannot expose a partially converted store.
actor LibraryStore: MemoStore, ImageStore {
    let originalFile: URL
    private let useSecurityScope: Bool
    private var root: URL { originalFile.deletingLastPathComponent() }
    private var manifestURL: URL { originalFile.appendingPathExtension("storage.json") }
    private var observed: [Memo.ID: String] = [:]
    private var scope: URL?
    private var scopeData: Data?

    private struct Location: Codable, Equatable {
        var markdown: Bool
        var path: String
        var bookmark: Data?
        var generation: UUID
        var recovery: String?
    }

    private struct IndexedFile: Codable, Equatable {
        var id: UUID
        var resource: UInt64
        var createdAt: Date
    }

    private struct Entry {
        var memo: Memo
        var url: URL
        var bytes: Data
    }

    init(fileURL: URL, useSecurityScope: Bool = true) {
        originalFile = fileURL
        self.useSecurityScope = useSecurityScope
    }

    deinit { scope?.stopAccessingSecurityScopedResource() }

    static func inApplicationSupport() throws -> LibraryStore {
        if let path = ProcessInfo.processInfo.environment["MEMOS_STORE"], !path.isEmpty {
            return LibraryStore(fileURL: URL(fileURLWithPath: path))
        }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return LibraryStore(fileURL: directory.appending(path: "store.json"))
    }

    func status() throws -> StorageStatus {
        try locked {
            let location = try active()
            return StorageStatus(markdown: location.markdown, location: URL(fileURLWithPath: location.path), recovery: location.recovery.map { URL(fileURLWithPath: $0) })
        }
    }

    func storedStatus() throws -> StorageStatus {
        try locked {
            let location = try JSONDecoder().decode(Location.self, from: Data(contentsOf: manifestURL))
            return try statusWithoutLock(location)
        }
    }

    func reconnect(to folder: URL) throws -> StorageStatus {
        try locked {
            var location = try JSONDecoder().decode(Location.self, from: Data(contentsOf: manifestURL))
            guard location.markdown else { throw StorageError.invalid("The current storage is internal.") }
            let marker = try String(contentsOf: folder.appending(path: ".memos-library"), encoding: .utf8)
            guard marker == location.generation.uuidString else { throw StorageError.invalid("Choose the original Memos folder, not a different library.") }
            location.path = folder.path
            location.bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            _ = try entries(at: location)
            try JSONEncoder().encode(location).write(to: manifestURL, options: .atomic)
            scopeData = nil
            return try statusWithoutLock(location)
        }
    }

    func revision() throws -> String {
        try locked {
            let location = try active()
            return location.path + (try fingerprints(location)).sorted { $0.key < $1.key }.map { $0.key + $0.value }.joined()
        }
    }

    func list(matching query: String?) throws -> [Memo] {
        try locked {
            let needle = query?.trimmingCharacters(in: .whitespaces) ?? ""
            return try entries(at: active()).map(\.memo)
                .filter { needle.isEmpty || $0.markdown.localizedCaseInsensitiveContains(needle) }
                .sorted {
                    if $0.favorite != $1.favorite { return $0.favorite }
                    if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
        }
    }

    func get(_ id: Memo.ID) throws -> Memo? {
        try locked {
            let entry = try entries(at: active()).first { $0.memo.id == id }
            if let entry { observed[id] = entry.memo.markdown }
            return entry?.memo
        }
    }

    func create(markdown: String) throws -> Memo {
        try locked {
            let location = try active()
            let now = Self.milliseconds(.now)
            let memo = Memo(id: UUID(), markdown: markdown, favorite: false, createdAt: now, updatedAt: now)
            try insert(memo, at: location)
            observed[memo.id] = markdown
            return memo
        }
    }

    func update(_ id: Memo.ID, markdown: String) throws -> Memo {
        try update(id, markdown: markdown, expecting: observed[id])
    }

    func update(_ id: Memo.ID, markdown: String, expecting baseline: String?) throws -> Memo {
        try locked {
            let location = try active()
            let all = try entries(at: location)
            guard let entry = all.first(where: { $0.memo.id == id }) else { throw MemoStoreError.missing(id) }
            if let baseline, entry.memo.markdown != baseline, entry.memo.markdown != markdown {
                throw StorageError.conflict(try recover(markdown))
            }
            var memo = entry.memo
            memo.markdown = markdown
            memo.updatedAt = Self.milliseconds(.now)
            try replace(entry, with: memo, in: all, at: location)
            observed[id] = markdown
            return memo
        }
    }

    func setFavorite(_ id: Memo.ID, _ favorite: Bool) throws -> Memo {
        try locked {
            let location = try active()
            let all = try entries(at: location)
            guard let entry = all.first(where: { $0.memo.id == id }) else { throw MemoStoreError.missing(id) }
            var memo = entry.memo
            memo.favorite = favorite
            try replace(entry, with: memo, in: all, at: location)
            return memo
        }
    }

    func delete(_ id: Memo.ID) throws {
        try locked {
            let location = try active()
            let all = try entries(at: location)
            guard let entry = all.first(where: { $0.memo.id == id }) else { return }
            if location.markdown {
                try coordinated(entry.url) {
                    guard try Data(contentsOf: entry.url) == entry.bytes else { throw StorageError.changedDuringConversion }
                    _ = try recover(entry.memo.markdown)
                    try FileManager.default.removeItem(at: entry.url)
                }
            } else {
                try JSONMemoStore.encodeMemos(all.filter { $0.memo.id != id }.map(\.memo)).write(to: URL(fileURLWithPath: location.path), options: .atomic)
            }
            observed[id] = nil
        }
    }

    /// A fresh directory is used every time. Retired files are recovery snapshots, never input to a later
    /// toggle, so notes deleted in either mode cannot come back on the next conversion.
    func convert(toMarkdown enabled: Bool, parent: URL? = nil, bookmark: Data? = nil) throws -> StorageStatus {
        try locked {
            let source = try active()
            if source.markdown == enabled { return try statusWithoutLock(source) }
            let sourceEntries = try entries(at: source)
            let fingerprint = try fingerprints(source, from: sourceEntries)
            let generation = UUID()
            let base: URL
            if enabled {
                guard let parent else { throw StorageError.invalid("Choose a folder for your Markdown files.") }
                base = parent
            } else {
                base = root.appending(path: "libraries")
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            }
            let staging = base.appending(path: ".memos-preparing-\(generation.uuidString.lowercased())")
            let destination = base.appending(path: "memos-\(generation.uuidString.lowercased().prefix(8))")
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw StorageError.invalid("The destination already exists. Choose another folder.") }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            // Only this attempt's uncommitted staging is removed. The source and any completed generation
            // remain available even if committing the pointer fails.
            defer { if FileManager.default.fileExists(atPath: staging.path) { try? FileManager.default.removeItem(at: staging) } }
            let staged = Location(markdown: enabled, path: enabled ? staging.path : staging.appending(path: "store.json").path, bookmark: nil, generation: generation)
            if enabled {
                for entry in sourceEntries { try insert(entry.memo, at: staged) }
            } else {
                try JSONMemoStore.encodeMemos(sourceEntries.map(\.memo)).write(to: URL(fileURLWithPath: staged.path), options: .atomic)
            }
            try copyImages(from: directory(source), to: staging, memos: sourceEntries.map(\.memo))
            let roundTrip = try entries(at: staged).map(\.memo).sorted { $0.id.uuidString < $1.id.uuidString }
            guard roundTrip == sourceEntries.map(\.memo).sorted(by: { $0.id.uuidString < $1.id.uuidString }) else {
                throw StorageError.invalid("The converted memos did not match the originals. Storage has not changed.")
            }
            guard try fingerprints(source) == fingerprint else { throw StorageError.changedDuringConversion }
            try Data(generation.uuidString.utf8).write(to: staging.appending(path: ".memos-library"), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: destination)
            let committed = Location(markdown: enabled, path: enabled ? destination.path : destination.appending(path: "store.json").path,
                                     bookmark: enabled && bookmark != nil ? try destination.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) : nil, generation: generation, recovery: source.path)
            try JSONEncoder().encode(committed).write(to: manifestURL, options: .atomic)
            observed.removeAll()
            return try statusWithoutLock(committed)
        }
    }

    func save(_ data: Data) throws -> ImageReference {
        try locked {
            guard let type = ImageType(sniffing: data) else { throw ImageStoreError.unsupported }
            let name = "\(Self.digest(data)).\(type.fileExtension)"
            let folder = try directory(active()).appending(path: ImageReference.folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: name)
            if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
            return ImageReference(path: "\(ImageReference.folder)/\(name)")
        }
    }

    func url(for path: String) -> URL? {
        guard ImageReference.isOurs(path) else { return nil }
        do { return try locked { try directory(active()).appending(path: path) } }
        catch { storageLog.error("image location: \(error.localizedDescription, privacy: .public)"); return nil }
    }

    func removeOrphans(keeping used: Set<String>) {
        // Retaining images protects unsaved edits in other processes and retired conversion snapshots.
        // Deletion needs an explicit retention policy, not a sweep based on one process's view.
    }

    private func active() throws -> Location {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return Location(markdown: false, path: originalFile.path, generation: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        }
        var location = try JSONDecoder().decode(Location.self, from: Data(contentsOf: manifestURL))
        if useSecurityScope, let bookmark = location.bookmark, bookmark != scopeData {
            var stale = false
            let parent = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            let accessed = parent.startAccessingSecurityScopedResource()
            guard accessed || FileManager.default.isReadableFile(atPath: parent.path) else { throw StorageError.invalid("Access to the Markdown folder was lost. Choose it again in Storage settings.") }
            scope?.stopAccessingSecurityScopedResource()
            scope = parent
            scopeData = bookmark
            location.path = parent.path
            if stale { location.bookmark = try parent.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
            try JSONEncoder().encode(location).write(to: manifestURL, options: .atomic)
        }
        // A missing committed store is an error, not an empty library that can overwrite recovery data.
        guard FileManager.default.fileExists(atPath: location.path) else { throw StorageError.invalid("The selected storage location is unavailable: \(location.path)") }
        return location
    }

    private func statusWithoutLock(_ location: Location) throws -> StorageStatus {
        StorageStatus(markdown: location.markdown, location: URL(fileURLWithPath: location.path), recovery: location.recovery.map { URL(fileURLWithPath: $0) })
    }

    private func directory(_ location: Location) -> URL {
        let url = URL(fileURLWithPath: location.path)
        return location.markdown ? url : url.deletingLastPathComponent()
    }

    private func entries(at location: Location) throws -> [Entry] {
        if !location.markdown {
            let url = URL(fileURLWithPath: location.path)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            let memos = try JSONMemoStore.decodeMemos(data)
            guard Set(memos.map(\.id)).count == memos.count else { throw StorageError.invalid("The store contains duplicate memo IDs.") }
            return memos.map { Entry(memo: $0, url: url, bytes: data) }
        }
        let folder = directory(location)
        let indexURL = root.appending(path: "index-\(location.generation.uuidString).json")
        let previous: [String: IndexedFile]
        if FileManager.default.fileExists(atPath: indexURL.path) { previous = try JSONDecoder().decode([String: IndexedFile].self, from: Data(contentsOf: indexURL)) }
        else { previous = [:] }
        var index: [String: IndexedFile] = [:]
        var result: [Entry] = []
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        for url in urls.filter({ $0.pathExtension.lowercased() == "md" }).sorted(by: { $0.path < $1.path }) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { throw StorageError.invalid("A Markdown entry is not a regular file: \(url.lastPathComponent)") }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let resource = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let match = previous[url.lastPathComponent] ?? previous.values.first { $0.resource == resource && resource != 0 }
            let created = match?.createdAt ?? (attributes[.creationDate] as? Date ?? .now)
            let fallback = Memo(id: match?.id ?? UUID(), markdown: "", favorite: false, createdAt: Self.milliseconds(created), updatedAt: Self.milliseconds(attributes[.modificationDate] as? Date ?? created))
            let bytes = try Data(contentsOf: url)
            var memo = try MarkdownDocument.decode(bytes, fallback: fallback)
            memo.updatedAt = max(memo.updatedAt, fallback.updatedAt)
            guard !result.contains(where: { $0.memo.id == memo.id }) else { throw StorageError.invalid("Duplicate memo ID in \(url.lastPathComponent). Neither file has been overwritten.") }
            index[url.lastPathComponent] = IndexedFile(id: memo.id, resource: resource, createdAt: memo.createdAt)
            result.append(Entry(memo: memo, url: url, bytes: bytes))
        }
        if index != previous { try JSONEncoder().encode(index).write(to: indexURL, options: .atomic) }
        return result
    }

    private func insert(_ memo: Memo, at location: Location) throws {
        if location.markdown {
            let stem = Memo.fileName(for: memo.title).dropLast(3).lowercased().replacing(/[^\p{L}\p{N}]+/, with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let filename = "\(stem.isEmpty ? "memo" : String(stem))-\(memo.id.uuidString.lowercased()).md"
            let url = directory(location).appending(path: filename)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw StorageError.invalid("A memo file already exists at the destination.") }
            try MarkdownDocument.encode(memo).write(to: url, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.modificationDate: memo.updatedAt], ofItemAtPath: url.path)
        } else {
            var memos = try entries(at: location).map(\.memo)
            memos.append(memo)
            try JSONMemoStore.encodeMemos(memos).write(to: URL(fileURLWithPath: location.path), options: .atomic)
        }
    }

    private func replace(_ entry: Entry, with memo: Memo, in all: [Entry], at location: Location) throws {
        try coordinated(entry.url) {
            guard try Data(contentsOf: entry.url) == entry.bytes else { throw StorageError.conflict(try recover(memo.markdown)) }
            if location.markdown {
                _ = try recover(entry.memo.markdown)
                try MarkdownDocument.encode(memo).write(to: entry.url, options: .atomic)
                try FileManager.default.setAttributes([.modificationDate: memo.updatedAt], ofItemAtPath: entry.url.path)
            } else {
                let memos = all.map { $0.memo.id == memo.id ? memo : $0.memo }
                try JSONMemoStore.encodeMemos(memos).write(to: entry.url, options: .atomic)
            }
        }
    }

    private func recover(_ markdown: String) throws -> URL {
        let folder = root.appending(path: "recovery")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "memo-\(Self.digest(Data(markdown.utf8))).md")
        if !FileManager.default.fileExists(atPath: url.path) { try Data(markdown.utf8).write(to: url, options: .atomic) }
        return url
    }

    private func imagePaths(in directory: URL, memos: [Memo]) throws -> Set<String> {
        var paths = memos.reduce(into: Set<String>()) { $0.formUnion(ImageReference.references(in: $1.markdown)) }
        let folder = directory.appending(path: ImageReference.folder)
        if FileManager.default.fileExists(atPath: folder.path) {
            for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else { throw StorageError.invalid("An image is not a regular file: \(url.lastPathComponent)") }
                paths.insert("\(ImageReference.folder)/\(url.lastPathComponent)")
            }
        }
        return paths
    }

    private func copyImages(from source: URL, to target: URL, memos: [Memo]) throws {
        let paths = try imagePaths(in: source, memos: memos)
        if !paths.isEmpty { try FileManager.default.createDirectory(at: target.appending(path: ImageReference.folder), withIntermediateDirectories: true) }
        for path in paths {
            let data = try Data(contentsOf: source.appending(path: path))
            let destination = target.appending(path: path)
            try data.write(to: destination, options: .atomic)
            guard try Data(contentsOf: destination) == data else { throw StorageError.invalid("An image could not be verified.") }
        }
    }

    private func fingerprints(_ location: Location, from snapshot: [Entry]? = nil) throws -> [String: String] {
        let all = try snapshot ?? entries(at: location)
        var result: [String: String] = [:]
        for entry in all { result[entry.url.lastPathComponent] = Self.digest(entry.bytes) }
        for path in try imagePaths(in: directory(location), memos: all.map(\.memo)) {
            result[path] = Self.digest(try Data(contentsOf: directory(location).appending(path: path)))
        }
        return result
    }

    private func coordinated<T>(_ url: URL, body: () throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { _ in
            result = Result { try body() }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw StorageError.invalid("File coordination did not complete.") }
        return try result.get()
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = originalFile.appendingPathExtension("lock")
        let descriptor = open(url.path, O_RDWR | O_CREAT, 0o600)
        guard descriptor >= 0 else { throw MemoStoreError.locked(url, errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw MemoStoreError.locked(url, errno) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func milliseconds(_ date: Date) -> Date { JSONMemoStore.canonicalDate(date) }
}
