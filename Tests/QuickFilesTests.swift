import Foundation
import Testing
@testable import Memos

@MainActor
@Suite struct QuickFilesTests {
    private func fixture() throws -> (QuickFiles, ChangeableStore, URL, UserDefaults, () -> String?) {
        let root = FileManager.default.temporaryDirectory.appending(path: "quick-files-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "quick-files-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = ChangeableStore([])
        let model = AppModel(store: store, images: FakeImageStore(), defaults: defaults, editor: FakeEditor())
        var copiedPath: String?
        let files = QuickFiles(memoModel: model, defaults: defaults, defaultFolder: root,
                               presentsWindow: false, copyPath: { copiedPath = $0 })
        return (files, store, root, defaults, { copiedPath })
    }

    @Test func disabledByDefaultAndPreferencesPersist() throws {
        let (files, _, root, defaults, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!files.enabled)
        #expect(files.format == .txt)
        files.enabled = true
        files.format = .md
        #expect(defaults.bool(forKey: "quickFiles.enabled"))
        #expect(defaults.string(forKey: "quickFiles.format") == "md")
    }

    @Test func dateNameAvoidsExistingFileAndCopiesPath() async throws {
        let (files, store, root, _, copiedPath) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_790_113_017)
        let first = QuickFiles.availableURL(in: root, format: .md, now: now)
        try Data("existing".utf8).write(to: first)
        let second = QuickFiles.availableURL(in: root, format: .md, now: now)
        #expect(second.lastPathComponent.contains("-2.md"))
        files.enabled = true
        files.format = .md
        files.text = "# Direct file\n"
        files.save()
        let saved = try #require(files.url)
        #expect(saved.pathExtension == "md")
        #expect(try String(contentsOf: saved, encoding: .utf8) == "# Direct file\n")
        #expect(copiedPath() == saved.path)
        #expect(await store.list(matching: nil).isEmpty)
    }

    @Test func openedTextRoundTripsAndRefusesExternalOverwrite() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "opened.txt")
        try Data("first\n".utf8).write(to: url)
        files.enabled = true
        files.open(url)
        #expect(files.text == "first\n")
        files.text = "second\n"
        files.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == "second\n")
        try Data("outside\n".utf8).write(to: url)
        files.text = "my edit\n"
        files.save()
        #expect(files.error == QuickFileError.changed.localizedDescription)
        #expect(try String(contentsOf: url, encoding: .utf8) == "outside\n")
    }

    @Test func saveToMemosCopiesWithoutChangingFile() async throws {
        let (files, store, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.text = "# Keep both\n"
        files.save()
        let saved = try #require(files.url)
        await files.saveToMemos()
        #expect(await store.list(matching: nil).map(\.markdown) == ["# Keep both\n"])
        #expect(try String(contentsOf: saved, encoding: .utf8) == "# Keep both\n")
    }
}
