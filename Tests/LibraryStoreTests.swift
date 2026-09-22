import Foundation
import Testing
@testable import Memos

@Suite struct LibraryStoreTests {
    private func fixture() throws -> (LibraryStore, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "library-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (LibraryStore(fileURL: root.appending(path: "store.json")), root)
    }

    @Test func unsandboxedCLIUsesPathWithoutResolvingAppBookmark() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let memo = try await store.create(markdown: "Shared\n")
        _ = try await store.convert(toMarkdown: true, parent: root)
        let manifest = root.appending(path: "store.json.storage.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        object["bookmark"] = Data("app-specific bookmark".utf8).base64EncodedString()
        try JSONSerialization.data(withJSONObject: object).write(to: manifest)
        let cli = LibraryStore(fileURL: root.appending(path: "store.json"), useSecurityScope: false)
        #expect(try await cli.get(memo.id)?.markdown == memo.markdown)
        _ = try await cli.update(memo.id, markdown: "From CLI\n", expecting: memo.markdown)
        #expect(try await cli.get(memo.id)?.markdown == "From CLI\n")
    }

    @Test func timestampsDoNotDriftAcrossRepeatedEncoding() throws {
        for milliseconds in 740..<790 {
            var memo = Memo(id: UUID(), markdown: "Date\n", favorite: false,
                            createdAt: Date(timeIntervalSince1970: 1790113017 + Double(milliseconds) / 1000),
                            updatedAt: Date(timeIntervalSince1970: 1790113017 + Double(milliseconds) / 1000))
            memo = try #require(JSONMemoStore.decodeMemos(JSONMemoStore.encodeMemos([memo])).first)
            let original = memo
            for _ in 0..<10 {
                memo = try #require(JSONMemoStore.decodeMemos(JSONMemoStore.encodeMemos([memo])).first)
                #expect(memo == original)
            }
        }
    }

    @Test func conversionsPreserveMemosMetadataImagesAndDeletions() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3])
        let reference = try await store.save(image)
        let first = try await store.create(markdown: "# Test\n\n![Image](\(reference.path))\n")
        _ = try await store.setFavorite(first.id, true)
        let deleted = try await store.create(markdown: "Delete me\n")
        let original = try await store.list(matching: nil)
        let external = try await store.convert(toMarkdown: true, parent: root)
        #expect(external.markdown)
        #expect(try await store.list(matching: nil) == original)
        #expect(try Data(contentsOf: #require(await store.url(for: reference.path))) == image)
        let path = try #require(FileManager.default.contentsOfDirectory(at: external.location, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains(first.id.uuidString.lowercased()) })
        var bytes = try String(contentsOf: path, encoding: .utf8)
        bytes = bytes.replacingOccurrences(of: "# Test", with: "# Edited outside")
        try bytes.write(to: path, atomically: true, encoding: .utf8)
        #expect(try await store.get(first.id)?.markdown.hasPrefix("# Edited outside") == true)
        try await store.delete(deleted.id)
        let new = try await store.create(markdown: "Added in files\n")
        let inFiles = try await store.list(matching: nil)
        let internalStatus = try await store.convert(toMarkdown: false)
        #expect(!internalStatus.markdown)
        #expect(try await store.list(matching: nil) == inFiles)
        #expect(try await store.get(deleted.id) == nil)
        #expect(try await store.get(new.id) != nil)
        #expect(FileManager.default.fileExists(atPath: external.location.path))
        let again = try await store.convert(toMarkdown: true, parent: root)
        #expect(again.location != external.location)
        #expect(try await store.list(matching: nil) == inFiles)
        #expect(try Data(contentsOf: #require(await store.url(for: reference.path))) == image)
    }

    @Test func independentClientsFollowConversionAndRejectStaleEdits() async throws {
        let (app, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = LibraryStore(fileURL: root.appending(path: "store.json"))
        let first = try await app.create(markdown: "Original\n")
        _ = try await tool.get(first.id)
        _ = try await app.convert(toMarkdown: true, parent: root)
        _ = try await app.update(first.id, markdown: "App edit\n", expecting: first.markdown)
        await #expect(throws: StorageError.self) { try await tool.update(first.id, markdown: "Stale edit\n") }
        #expect(try await app.get(first.id)?.markdown == "App edit\n")
        let recovery = try FileManager.default.contentsOfDirectory(at: root.appending(path: "recovery"), includingPropertiesForKeys: nil)
        #expect(try recovery.contains { try String(contentsOf: $0, encoding: .utf8) == "Stale edit\n" })
        let second = try await tool.create(markdown: "Tool edit\n")
        #expect(try await app.get(second.id) != nil)
        _ = try await app.convert(toMarkdown: false)
        _ = try await tool.update(second.id, markdown: "After conversion\n", expecting: second.markdown)
        #expect(try await app.get(second.id)?.markdown == "After conversion\n")
    }

    @Test func failureLeavesTheCommittedSourceActive() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let memo = try await store.create(markdown: "![Missing](images/\(String(repeating: "a", count: 64)).png)\n")
        await #expect(throws: (any Error).self) { try await store.convert(toMarkdown: true, parent: root) }
        #expect(try await store.status().markdown == false)
        #expect(try await store.get(memo.id)?.markdown == memo.markdown)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "store.json.storage.json").path))
    }

    @Test func plainFilesKeepIdentityWhenRenamedAndAreNotRewrittenOnRead() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try await store.convert(toMarkdown: true, parent: root).location
        let path = folder.appending(path: "plain.md")
        let original = Data("---\ntitle: External\ncustom: [a, b]\n---\n# Plain\r\nno trailing newline".utf8)
        try original.write(to: path)
        let memo = try #require(await store.list(matching: nil).first)
        #expect(try Data(contentsOf: path) == original)
        let renamed = folder.appending(path: "renamed.md")
        try FileManager.default.moveItem(at: path, to: renamed)
        #expect(try await store.list(matching: nil).first?.id == memo.id)
        _ = try await store.setFavorite(memo.id, true)
        #expect(try await store.get(memo.id)?.markdown == memo.markdown)
        _ = try await store.convert(toMarkdown: false)
        #expect(try await store.get(memo.id)?.markdown == memo.markdown)
        _ = try await store.convert(toMarkdown: true, parent: root)
        #expect(try await store.get(memo.id)?.markdown == memo.markdown)
    }

    @Test func windowsLineEndingsPreserveMetadataAndForeignFrontmatter() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "---\r\ncustom: kept\r\n---\r\n# Windows\r\n"
        let memo = try await store.create(markdown: original)
        _ = try await store.setFavorite(memo.id, true)
        let folder = try await store.convert(toMarkdown: true, parent: root).location
        let file = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.pathExtension == "md" })
        let bytes = try Data(contentsOf: file)
        #expect(try await store.get(memo.id)?.markdown == original)
        #expect(try await store.get(memo.id)?.favorite == true)
        #expect(try Data(contentsOf: file) == bytes)
        _ = try await store.convert(toMarkdown: false)
        #expect(try await store.get(memo.id)?.markdown == original)
    }

    @Test func malformedAndDuplicateDocumentsCannotReplaceTheLibrary() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let memo = try await store.create(markdown: "Keep\n")
        let folder = try await store.convert(toMarkdown: true, parent: root).location
        let duplicate = folder.appending(path: "duplicate.md")
        try MarkdownDocument.encode(memo).write(to: duplicate)
        await #expect(throws: StorageError.self) { try await store.convert(toMarkdown: false) }
        #expect(try await store.status().markdown)
        try FileManager.default.removeItem(at: duplicate)
        let malformed = folder.appending(path: "broken.md")
        try Data("---\nmemos: {broken}\n---\nKeep\n".utf8).write(to: malformed)
        await #expect(throws: (any Error).self) { try await store.convert(toMarkdown: false) }
        #expect(try await store.status().markdown)
    }

    @Test func committedMissingFolderDoesNotFallBackToOldJSON() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.create(markdown: "Original\n")
        let folder = try await store.convert(toMarkdown: true, parent: root).location
        try FileManager.default.moveItem(at: folder, to: root.appending(path: "moved"))
        let reopened = LibraryStore(fileURL: root.appending(path: "store.json"))
        await #expect(throws: StorageError.self) { try await reopened.list(matching: nil) }
    }

    @Test func uncommittedGenerationIsIgnoredAfterRelaunch() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let memo = try await store.create(markdown: "Committed\n")
        let orphan = root.appending(path: ".memos-preparing-interrupted")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("Partial".utf8).write(to: orphan.appending(path: "partial.md"))
        let reopened = LibraryStore(fileURL: root.appending(path: "store.json"))
        #expect(try await reopened.list(matching: nil).map(\.id) == [memo.id])
        #expect(try await reopened.status().markdown == false)
    }

    @Test func multipleWritersPreserveAllMemos() async throws {
        let (store, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await store.convert(toMarkdown: true, parent: root)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let writer = LibraryStore(fileURL: root.appending(path: "store.json"))
                    _ = try await writer.create(markdown: "Memo \(index)\n")
                }
            }
            try await group.waitForAll()
        }
        #expect(try await store.list(matching: nil).count == 20)
    }
}


@MainActor
@Suite struct LibraryModelTests {
    @Test func concurrentExternalEditKeepsBothVersionsInTheApp() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "model-library-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(fileURL: root.appending(path: "store.json"))
        let original = try await store.create(markdown: "Original\n")
        _ = try await store.convert(toMarkdown: true, parent: root)
        let editor = FakeEditor()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(store: store, images: store, defaults: defaults, editor: editor)
        await model.start()
        editor.type("Typed here\n")
        let external = LibraryStore(fileURL: root.appending(path: "store.json"))
        _ = try await external.update(original.id, markdown: "Changed outside\n", expecting: original.markdown)
        model.storeChanged()
        await model.settle()
        let all = try await store.list(matching: nil)
        #expect(Set(all.map(\.markdown)) == Set(["Typed here\n", "Changed outside\n"]))
        #expect(model.current?.markdown == "Typed here\n")
        #expect(model.current?.id != original.id)
        #expect(model.storageNotice != nil)
    }

    @Test func frontmatterDoesNotBecomeTheMemoTitle() {
        #expect(Memo.title(for: "---\ncustom: kept\n---\n# Actual title\n") == "Actual title")
    }
}
