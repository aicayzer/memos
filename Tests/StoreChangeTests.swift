import Foundation
import Testing
@testable import Memos

/// A store whose file another process can change, as the command line tool does.
actor ChangeableStore: MemoStore {
    enum Recovery: CaseIterable, Sendable { case conflict, missing }
    var memos: [Memo]
    private var recovery: Recovery?
    private var delayingCreate = false
    private var createContinuation: CheckedContinuation<Void, Never>?
    private var createStarted: CheckedContinuation<Void, Never>?

    init(_ memos: [Memo]) { self.memos = memos }

    func list(matching query: String?) -> [Memo] { memos }
    func get(_ id: Memo.ID) -> Memo? { memos.first { $0.id == id } }

    func create(markdown: String) async -> Memo {
        if delayingCreate {
            delayingCreate = false
            await withCheckedContinuation { continuation in
                createContinuation = continuation
                createStarted?.resume()
                createStarted = nil
            }
        }
        let memo = Memo(id: UUID(), markdown: markdown, favorite: false, createdAt: .now, updatedAt: .now)
        memos.insert(memo, at: 0)
        return memo
    }

    func update(_ id: Memo.ID, markdown: String) throws -> Memo {
        guard let index = memos.firstIndex(where: { $0.id == id }) else { throw MemoStoreError.missing(id) }
        memos[index].markdown = markdown
        memos[index].updatedAt = .now
        return memos[index]
    }

    func update(_ id: Memo.ID, markdown: String, expecting baseline: String?) throws -> Memo {
        if let recovery {
            self.recovery = nil
            switch recovery {
            case .conflict: throw StorageError.conflict(FileManager.default.temporaryDirectory.appending(path: "fixture-memo.md"))
            case .missing:
                memos.removeAll { $0.id == id }
                throw MemoStoreError.missing(id)
            }
        }
        return try update(id, markdown: markdown)
    }

    func delayRecovery(_ recovery: Recovery) {
        self.recovery = recovery
        delayingCreate = true
    }

    func waitForRecoveryCreate() async {
        guard createContinuation == nil else { return }
        await withCheckedContinuation { createStarted = $0 }
    }

    func finishRecoveryCreate() {
        createContinuation?.resume()
        createContinuation = nil
    }

    func setFavorite(_ id: Memo.ID, _ favorite: Bool) throws -> Memo {
        guard let index = memos.firstIndex(where: { $0.id == id }) else { throw MemoStoreError.missing(id) }
        memos[index].favorite = favorite
        return memos[index]
    }

    func delete(_ id: Memo.ID) { memos.removeAll { $0.id == id } }

    /// What the other process did.
    func replace(_ id: Memo.ID, with markdown: String, favorite: Bool? = nil) {
        guard let index = memos.firstIndex(where: { $0.id == id }) else { return }
        memos[index].markdown = markdown
        if let favorite { memos[index].favorite = favorite }
    }
}

@MainActor
@Suite struct StoreChangeTests {
    private func model() async -> (AppModel, ChangeableStore, Memo) {
        let memo = Memo(id: UUID(), markdown: "On screen\n", favorite: false, createdAt: .now, updatedAt: .now)
        let store = ChangeableStore([memo])
        let defaults = UserDefaults(suiteName: "store-change-tests")!
        defaults.removePersistentDomain(forName: "store-change-tests")
        let model = AppModel(store: store, images: FakeImageStore(), defaults: defaults, editor: FakeEditor(), presentError: { _ in })
        await model.start()
        return (model, store, memo)
    }

    @Test func aChangeOutsideReachesTheMemoOnScreen() async throws {
        let (model, store, memo) = await model()
        await store.replace(memo.id, with: "Changed elsewhere\n")
        model.storeChanged()
        await model.settle()
        #expect(model.current?.markdown == "Changed elsewhere\n")
        #expect(model.storeGeneration == 1)
    }

    @Test func aFavoriteChangeOutsideDoesNotReloadTheText() async throws {
        let (model, store, memo) = await model()
        await store.replace(memo.id, with: memo.markdown, favorite: true)
        model.storeChanged()
        await model.settle()
        #expect(model.current?.favorite == true)
        #expect(model.current?.markdown == memo.markdown)
    }

    @Test func anEditInFlightKeepsItsText() async throws {
        let (model, store, memo) = await model()
        (model.editor as! FakeEditor).type("Typed here\n")
        await store.replace(memo.id, with: "Changed elsewhere\n")
        model.storeChanged()
        await model.settle()
        #expect(model.current?.markdown == "Typed here\n")
        #expect(await store.get(memo.id)?.markdown == "Typed here\n")
    }

    @Test func aMemoDeletedUnderAnEditComesBackWithTheText() async throws {
        let (model, store, memo) = await model()
        (model.editor as! FakeEditor).type("Typed here\n")
        await store.delete(memo.id)
        model.storeChanged()
        await model.settle()
        #expect(model.current?.markdown == "Typed here\n")
        #expect(model.current?.id != memo.id)
        #expect(model.editor.documentID == model.current?.id.uuidString)
        #expect((model.editor as! FakeEditor).generation == 2)
        #expect(await store.list(matching: nil).map(\.markdown) == ["Typed here\n"])
    }

    @Test func aMemoDeletedWhileIdleGivesWayToTheNewest() async throws {
        let (model, store, memo) = await model()
        let other = await store.create(markdown: "Other\n")
        await store.delete(memo.id)
        model.storeChanged()
        await model.settle()
        #expect(model.current?.id == other.id)
    }

    @Test func aChangeOutsideIsShownWithoutMovingTheCaret() async throws {
        let (model, store, memo) = await model()
        let editor = model.editor as! FakeEditor
        await store.replace(memo.id, with: "Changed elsewhere\n")
        model.storeChanged()
        await model.settle()
        #expect(editor.reloaded == ["Changed elsewhere\n"])
        #expect(editor.loaded == ["On screen\n"])
    }

    @Test func anEditUnderAChangeOutsideIsWrittenFirst() async throws {
        let (model, store, memo) = await model()
        let editor = model.editor as! FakeEditor
        editor.type("Typed here\n")
        await store.replace(memo.id, with: "Changed elsewhere\n")
        model.storeChanged()
        await model.settle()
        // The app's edit wins for this memo, and the window shows what the store then holds.
        #expect(await store.get(memo.id)?.markdown == "Typed here\n")
        #expect(model.current?.markdown == "Typed here\n")
        #expect(editor.reloaded.isEmpty)
    }

    @Test func aFailedSnapshotStopsAnExternalReload() async throws {
        let (model, store, memo) = await model()
        let editor = model.editor as! FakeEditor
        editor.typeWithoutReporting("Unreported edit\n")
        editor.snapshotError = MemoEditorError.unavailable
        await store.replace(memo.id, with: "Changed elsewhere\n")
        model.storeChanged()
        await model.settle()
        #expect(model.current?.markdown == memo.markdown)
        #expect(editor.text == "Unreported edit\n")
        #expect(editor.reloaded.isEmpty)
        #expect(await store.get(memo.id)?.markdown == "Changed elsewhere\n")
    }

    @Test(arguments: ChangeableStore.Recovery.allCases, [false, true])
    func recoveryRebindsTheLatestReportedOrUnreportedText(_ recovery: ChangeableStore.Recovery, _ reporting: Bool) async throws {
        let (model, store, memo) = await model()
        let editor = model.editor as! FakeEditor
        editor.type("First edit\n")
        await store.delayRecovery(recovery)
        let saving = Task { await model.flush() }
        await store.waitForRecoveryCreate()
        if reporting { editor.type("Newer pending edit\n") } else { editor.typeWithoutReporting("Newer pending edit\n") }
        await store.finishRecoveryCreate()
        #expect(await saving.value)
        let recovered = try #require(model.current)
        #expect(recovered.id != memo.id)
        #expect(recovered.markdown == "Newer pending edit\n")
        #expect(editor.text == recovered.markdown)
        #expect(editor.documentID == recovered.id.uuidString)
        #expect(editor.generation == 2)
        #expect(await store.get(recovered.id)?.markdown == "First edit\n")
        #expect(await model.flush())
        #expect(await store.get(recovered.id)?.markdown == "Newer pending edit\n")
    }

    @Test(arguments: ChangeableStore.Recovery.allCases)
    func failedRecoverySnapshotKeepsTheOriginalEditorAndNewerText(_ recovery: ChangeableStore.Recovery) async throws {
        let (model, store, memo) = await model()
        let editor = model.editor as! FakeEditor
        editor.type("First edit\n")
        await store.delayRecovery(recovery)
        let saving = Task { await model.flush() }
        await store.waitForRecoveryCreate()
        editor.type("Newer pending edit\n")
        editor.snapshotError = MemoEditorError.notReady
        await store.finishRecoveryCreate()
        #expect(!(await saving.value))
        #expect(model.current?.id == memo.id)
        #expect(model.current?.markdown == "Newer pending edit\n")
        #expect(editor.text == "Newer pending edit\n")
        #expect(editor.documentID == memo.id.uuidString)
        #expect(editor.generation == 1)
        #expect(await store.list(matching: nil).contains { $0.id != memo.id && $0.markdown == "First edit\n" })
    }

    @Test func anEditReportedWhileRecoveryReturnsRemainsPending() async throws {
        let (model, store, _) = await model()
        let editor = model.editor as! FakeEditor
        editor.type("First edit\n")
        await store.delayRecovery(.missing)
        editor.duringRebind = { editor.type("Typed after rebinding\n") }
        let saving = Task { await model.flush() }
        await store.waitForRecoveryCreate()
        await store.finishRecoveryCreate()
        #expect(await saving.value)
        let recovered = try #require(model.current)
        #expect(recovered.markdown == "Typed after rebinding\n")
        #expect(editor.text == recovered.markdown)
        #expect(editor.documentID == recovered.id.uuidString)
        #expect(await model.flush())
        #expect(await store.get(recovered.id)?.markdown == "Typed after rebinding\n")
    }

    @Test(arguments: ChangeableStore.Recovery.allCases)
    func aMemoOpenedDuringRecoveryKeepsItsOwnEditorIdentity(_ recovery: ChangeableStore.Recovery) async throws {
        let (model, store, _) = await model()
        let editor = model.editor as! FakeEditor
        editor.type("First edit\n")
        await store.delayRecovery(recovery)
        let saving = Task { await model.flush() }
        await store.waitForRecoveryCreate()
        let other = await store.create(markdown: "Other memo\n")
        await model.open(other.id)
        await store.finishRecoveryCreate()
        #expect(await saving.value)
        #expect(model.current?.id == other.id)
        #expect(editor.documentID == other.id.uuidString)
        #expect(editor.text == other.markdown)
        #expect(editor.generation == 2)
    }
}
