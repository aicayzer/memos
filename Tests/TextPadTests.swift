import AppKit
import Testing
@testable import Memos

@MainActor
@Suite struct TextPadTests {
    private func fixture(
        selectOpenFile: (@MainActor () async -> URL?)? = nil,
        selectSaveFile: (@MainActor (URL, String) async -> URL?)? = nil,
        discardChanges: @escaping @MainActor () -> Bool = { false }
    ) throws -> (TextPad, ChangeableStore, URL, UserDefaults, () -> String?) {
        let root = FileManager.default.temporaryDirectory.appending(path: "textpad-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "textpad-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = ChangeableStore([])
        let model = AppModel(store: store, images: FakeImageStore(), defaults: defaults, editor: FakeEditor())
        var copiedPath: String?
        let files = TextPad(memoModel: model, defaults: defaults, defaultFolder: root,
                            presentsWindow: false, copyPath: { copiedPath = $0 },
                            selectOpenFile: selectOpenFile, selectSaveFile: selectSaveFile,
                            discardChanges: discardChanges)
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

    @Test func reopeningCleanFileReloadsExternalChanges() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "external.md")
        try Data("original".utf8).write(to: url)
        files.enabled = true
        files.open(url)
        try Data("external edit".utf8).write(to: url)
        files.open(url)
        #expect(files.text == "external edit")
        #expect(!files.isDirty)
        files.text = "my next edit"
        files.save()
        #expect(files.error == nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == "my next edit")
    }

    @Test func reopeningDirtyFileKeepsLocalTextAndReportsConflict() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "external.txt")
        try Data("original".utf8).write(to: url)
        files.enabled = true
        files.open(url)
        files.text = "local edit"
        files.open(url)
        #expect(files.text == "local edit")
        #expect(files.error == nil)
        try Data("external edit".utf8).write(to: url)
        files.open(url)
        #expect(files.text == "local edit")
        #expect(files.savedText == "original")
        #expect(files.error == TextPadError.changed.localizedDescription)
        files.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == "external edit")
    }

    @Test func shortcutAndCommandNewRefreshSavedFiles() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        let now = Date.now
        files.newFile(now: now)
        files.text = "scratch"
        files.close()
        let saved = try #require(files.url)
        try Data("changed scratch".utf8).write(to: saved)
        files.commandNew(now: now.addingTimeInterval(1))
        #expect(files.text == "changed scratch")
        let opened = root.appending(path: "opened.txt")
        try Data("disk file".utf8).write(to: opened)
        files.open(opened)
        files.close()
        try Data("changed disk file".utf8).write(to: opened)
        files.toggle()
        #expect(files.text == "changed disk file")
        #expect(!files.isDirty)
        try FileManager.default.removeItem(at: opened)
        files.toggle()
        #expect(files.text == "changed disk file")
        #expect(files.error != nil)
    }

    @Test func savedScratchRequiresDiscardConfirmation() throws {
        let decision = TextPadDiscardDecision()
        let (files, _, root, _, _) = try fixture(discardChanges: {
            decision.confirmations += 1
            return decision.discard
        })
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.saveAutomatically = false
        files.newFile()
        files.text = "saved scratch"
        files.save()
        let saved = try #require(files.url)
        files.text = "unsaved edit"
        files.close()
        #expect(files.text == "unsaved edit")
        #expect(files.isDirty)
        #expect(decision.confirmations == 1)
        decision.discard = true
        files.close()
        #expect(decision.confirmations == 2)
        #expect(files.text == "saved scratch")
        #expect(files.url == saved)
        #expect(!files.isDirty)
    }

    @Test func pendingSaveAsGuardsDocumentAndSavesTheRequestedSnapshot() async throws {
        let selection = PendingTextPadSelection()
        let (files, _, root, _, _) = try fixture(selectSaveFile: { _, _ in await selection.select() })
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.text = "original"
        files.save()
        let original = try #require(files.url)
        let destination = root.appending(path: "save-as.md")
        let other = root.appending(path: "other.txt")
        try Data("other".utf8).write(to: other)
        files.text = "save this"
        let task = Task { await files.saveAs() }
        await selection.waitUntilPresented()
        #expect(files.isBusy)
        files.save()
        files.close()
        files.newFile()
        files.commandNew()
        files.toggle()
        files.open(other)
        await files.openPicker()
        await files.saveAs()
        await files.saveToMemos()
        #expect(!files.canTerminate())
        #expect(files.url == original)
        #expect(files.text == "save this")
        #expect(try String(contentsOf: original, encoding: .utf8) == "original")
        // A late programmatic edit must remain dirty after the requested snapshot is saved.
        files.text = "later edit"
        selection.complete(destination)
        await task.value
        #expect(!files.isBusy)
        #expect(files.url == destination)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "save this")
        #expect(files.text == "later edit")
        #expect(files.isDirty)
    }

    @Test func canceledAndFailedSaveAsPreserveDocument() async throws {
        let selection = PendingTextPadSelection()
        let (files, _, root, _, _) = try fixture(selectSaveFile: { _, _ in await selection.select() })
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.text = "original"
        files.save()
        let original = try #require(files.url)
        files.text = "local edit"
        let canceled = Task { await files.saveAs() }
        await selection.waitUntilPresented()
        selection.complete(nil)
        await canceled.value
        #expect(!files.isBusy)
        #expect(files.url == original)
        #expect(files.text == "local edit")
        let failed = Task { await files.saveAs() }
        await selection.waitUntilPresented()
        selection.complete(root.appending(path: "missing/fail.txt"))
        await failed.value
        #expect(!files.isBusy)
        #expect(files.url == original)
        #expect(files.isDirty)
        #expect(files.error != nil)
        #expect(try String(contentsOf: original, encoding: .utf8) == "original")
    }

    @Test func openPanelCancellationAndAcceptanceProtectCurrentEdits() async throws {
        let selection = PendingTextPadSelection()
        let (files, _, root, _, _) = try fixture(selectOpenFile: { await selection.select() })
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.text = "original"
        files.save()
        let original = try #require(files.url)
        let other = root.appending(path: "other.txt")
        try Data("other".utf8).write(to: other)
        files.text = "local edit"
        let canceled = Task { await files.openPicker() }
        await selection.waitUntilPresented()
        files.newFile()
        files.open(other)
        files.save()
        files.close()
        #expect(!files.canTerminate())
        #expect(files.text == "local edit")
        selection.complete(nil)
        await canceled.value
        #expect(!files.isBusy)
        #expect(files.url == original)
        #expect(try String(contentsOf: original, encoding: .utf8) == "original")
        let accepted = Task { await files.openPicker() }
        await selection.waitUntilPresented()
        selection.complete(other)
        await accepted.value
        #expect(!files.isBusy)
        #expect(files.url == other)
        #expect(files.text == "other")
        #expect(try String(contentsOf: original, encoding: .utf8) == "local edit")
    }

    @Test func discardPromptPreventsReentrantTransitions() throws {
        let decision = TextPadDiscardDecision()
        let (files, _, root, _, _) = try fixture(discardChanges: {
            decision.confirmations += 1
            decision.current?.newFile()
            decision.current?.close()
            decision.current?.save()
            #expect(decision.current?.canTerminate() == false)
            return false
        })
        decision.current = files
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.saveAutomatically = false
        files.text = "saved"
        files.save()
        let saved = try #require(files.url)
        files.text = "unsaved"
        files.newFile()
        #expect(decision.confirmations == 1)
        #expect(!files.isBusy)
        #expect(files.url == saved)
        #expect(files.text == "unsaved")
        #expect(try String(contentsOf: saved, encoding: .utf8) == "saved")
    }

    @Test func failedAutosaveBlocksCloseAndDocumentReplacement() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.text = "saved"
        files.save()
        let saved = try #require(files.url)
        try Data("external".utf8).write(to: saved)
        files.text = "local"
        files.close()
        files.newFile()
        #expect(!files.canTerminate())
        #expect(files.url == saved)
        #expect(files.text == "local")
        #expect(files.error == TextPadError.changed.localizedDescription)
        #expect(try String(contentsOf: saved, encoding: .utf8) == "external")
    }

    @Test func nonactivatingPanelRoutesCommandNewDirectly() throws {
        let (files, _, root, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        files.enabled = true
        files.reusePeriod = .alwaysNew
        files.newFile()
        files.text = "previous"
        let panel = TextPadPanel(files: files)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45
        ))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.performKeyEquivalent(with: event))
        #expect(files.text.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 1)
        panel.orderOut(nil)
    }
}

@MainActor
private final class TextPadDiscardDecision {
    var discard = false
    var confirmations = 0
    weak var current: TextPad?
}

@MainActor
private final class PendingTextPadSelection {
    private var selection: CheckedContinuation<URL?, Never>?
    private var presentation: CheckedContinuation<Void, Never>?

    func select() async -> URL? {
        await withCheckedContinuation { continuation in
            selection = continuation
            presentation?.resume()
            presentation = nil
        }
    }

    func waitUntilPresented() async {
        guard selection == nil else { return }
        await withCheckedContinuation { presentation = $0 }
    }

    func complete(_ url: URL?) {
        selection?.resume(returning: url)
        selection = nil
    }
}
