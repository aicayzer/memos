import Foundation
import Testing
@testable import Memos

/// The watcher asks for a revision every second. These cover what it must notice, and that an unchanged
/// library is answered from file stamps alone.
@Suite struct LibraryRevisionTests {
    private static let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

    private func fixture(markdown: Bool) async throws -> (LibraryStore, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "revision-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(fileURL: root.appending(path: "store.json"), useSecurityScope: false, settleTime: .zero)
        let image = try await store.save(Self.png + Data("first".utf8))
        _ = try await store.create(markdown: "# First\n\n![](\(image.path))\n")
        _ = try await store.create(markdown: "Second\n")
        if markdown { _ = try await store.convert(toMarkdown: true, parent: root) }
        let folder = try await store.status().location
        return (store, root, markdown ? folder : folder.deletingLastPathComponent())
    }

    private func memoFiles(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }.sorted { $0.path < $1.path }
    }

    /// Two writes never share a file system timestamp in practice; the pause keeps the tests from relying
    /// on the clock's resolution.
    private func pause() async throws { try await Task.sleep(for: .milliseconds(5)) }

    @Test(arguments: [false, true])
    func unchangedLibraryIsNotReread(markdown: Bool) async throws {
        let (store, root, _) = try await fixture(markdown: markdown)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await store.revision()
        let reads = await store.contentReads
        for _ in 0..<5 { #expect(try await store.revision() == first) }
        #expect(await store.contentReads == reads)
        let fresh = LibraryStore(fileURL: root.appending(path: "store.json"), useSecurityScope: false)
        #expect(try await fresh.revision() == first)
    }

    @Test func recentlyChangedFilesAreRereadUntilTheySettle() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "revision-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(fileURL: root.appending(path: "store.json"), useSecurityScope: false, settleTime: .seconds(60))
        _ = try await store.create(markdown: "Fresh\n")
        _ = try await store.revision()
        _ = try await store.revision()
        #expect(await store.contentReads == 2)
    }

    @Test func inPlaceEditByAnotherEditorIsNoticed() async throws {
        let (store, root, folder) = try await fixture(markdown: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.revision()
        let file = try #require(try memoFiles(in: folder).first { try String(contentsOf: $0, encoding: .utf8).contains("Second") })
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let original = try Data(contentsOf: file)
        try await pause()
        // Same length, same file, and the old modification date put back, as some editors and sync tools do.
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "Second", with: "Edited").utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: file.path)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int == attributes[.systemFileNumber] as? Int)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int == attributes[.size] as? Int)
        #expect(try await store.revision() != before)
    }

    @Test(arguments: [false, true])
    func addedImageIsNoticed(markdown: Bool) async throws {
        let (store, root, folder) = try await fixture(markdown: markdown)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.revision()
        try await pause()
        let other = LibraryStore(fileURL: root.appending(path: "store.json"), useSecurityScope: false)
        _ = try await other.save(Self.png + Data("second".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: ImageReference.folder).path).count == 2)
        #expect(try await store.revision() != before)
    }

    @Test(arguments: [false, true])
    func removedMemoIsNoticed(markdown: Bool) async throws {
        let (store, root, folder) = try await fixture(markdown: markdown)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.revision()
        try await pause()
        if markdown {
            try FileManager.default.removeItem(at: try #require(try memoFiles(in: folder).first))
        } else {
            let other = LibraryStore(fileURL: root.appending(path: "store.json"), useSecurityScope: false)
            try await other.delete(try #require(try await other.list(matching: nil).first).id)
        }
        #expect(try await store.revision() != before)
    }

    @Test func storageRelocationIsNoticed() async throws {
        let (store, root, _) = try await fixture(markdown: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let inStore = try await store.revision()
        let other = LibraryStore(fileURL: root.appending(path: "store.json"), useSecurityScope: false)
        _ = try await other.convert(toMarkdown: true, parent: root)
        let files = try await store.revision()
        #expect(files != inStore)
        _ = try await other.convert(toMarkdown: false)
        #expect(try await store.revision() != files)
    }

    @Test func rewritingIdenticalBytesKeepsTheRevision() async throws {
        let (store, root, folder) = try await fixture(markdown: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try await store.revision()
        let reads = await store.contentReads
        try await pause()
        let file = try #require(try memoFiles(in: folder).first)
        try Data(contentsOf: file).write(to: file, options: .atomic)
        #expect(try await store.revision() == before)
        #expect(await store.contentReads == reads + 1)
    }
}
