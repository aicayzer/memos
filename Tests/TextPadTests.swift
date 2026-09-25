import Foundation
import Testing
@testable import Memos

@MainActor
@Suite struct TextPadTests {
    private func fixture() throws -> (TextPad, ChangeableStore, URL, UserDefaults, () -> String?) {
        let root = FileManager.default.temporaryDirectory.appending(path: "textpad-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "textpad-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = ChangeableStore([])
        let model = AppModel(store: store, images: FakeImageStore(), defaults: defaults, editor: FakeEditor())
        var copiedPath: String?
        let files = TextPad(memoModel: model, defaults: defaults, defaultFolder: root,
                               presentsWindow: false, copyPath: { copiedPath = $0 })
        return (files, store, root, defaults, { copiedPath })
    }

    @Test func disabledByDefaultAndPreferencesPersist() throws {
        let (files, _, root, defaults, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!files.enabled)
        #expect(files.format == .txt)
        #expect(files.saveAutomatically)
        #expect(files.reusePeriod == .fifteenMinutes)
        files.enabled = true
        files.format = .md
        files.saveAutomatically = false
        files.reusePeriod = .fiveMinutes
        #expect(defaults.bool(forKey: "textPad.enabled"))
        #expect(defaults.string(forKey: "textPad.format") == "md")
        #expect(defaults.bool(forKey: "textPad.saveAutomatically") == false)
        #expect(defaults.integer(forKey: "textPad.reusePeriod") == 5)
    }

    @Test func dateNameAvoidsExistingFileAndCopiesPath() async throws {
        let (files, store, root, _, copiedPath) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_790_113_017)
        let first = TextPad.availableURL(in: root, format: .md, now: now)
        try Data("existing".utf8).write(to: first)
        let second = TextPad.availableURL(in: root, format: .md, now: now)
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
        #expect(files.error == TextPadError.changed.localizedDescription)
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

    @Test func reusePeriodsRecentDocumentAndStartsNewAfterInterval() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        let start = Date(timeIntervalSince1970: 1_790_113_017)
        files.newFile(now: start)
        files.text = "first"
        files.commandNew(now: start.addingTimeInterval(14 * 60))
        #expect(files.text == "first")
        files.commandNew(now: start.addingTimeInterval(15 * 60))
        #expect(files.text.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 1)
    }

    @Test func shortcutReopensCurrentDocumentWithinInterval() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        let start = Date(timeIntervalSince1970: 1_790_113_017)
        files.newFile(now: start)
        files.text = "hello world"
        files.close()
        let saved = try #require(files.url)
        files.toggle(now: start.addingTimeInterval(14 * 60))
        #expect(files.text == "hello world")
        #expect(files.url == saved)
        files.toggle(now: start.addingTimeInterval(15 * 60))
        #expect(files.text.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 1)
    }

    @Test func sharingDirtyTextUsesTemporaryCopyWithoutChangingOriginal() throws {
        let (files, _, root, _, _) = try fixture()
        let temporary = FileManager.default.temporaryDirectory.appending(path: "textpad-share-tests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: temporary)
        }
        files.enabled = true
        files.text = "scratch"
        let unsaved = try files.shareableURL(in: temporary)
        #expect(files.url == nil)
        #expect(unsaved.pathExtension == "txt")
        #expect(try String(contentsOf: unsaved, encoding: .utf8) == "scratch")

        files.save()
        let original = try #require(files.url)
        #expect(try files.shareableURL(in: temporary) == original)
        files.text = "changed"
        let shared = try files.shareableURL(in: temporary)
        #expect(shared != original)
        #expect(try String(contentsOf: shared, encoding: .utf8) == "changed")
        #expect(try String(contentsOf: original, encoding: .utf8) == "scratch")
    }

    @Test func freshTriggerSavesPreviousFileWhileScratchModeDiscardsIt() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.newFile()
        files.text = "keep"
        files.newFile()
        #expect(files.text.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 1)

        files.saveAutomatically = false
        files.text = "scratch"
        files.close()
        #expect(files.text.isEmpty)
        #expect(files.url == nil)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 1)
    }
}
