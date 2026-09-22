import Foundation
import Testing
@testable import Memos

/// A store whose file another process can change, as the command line tool does.
actor ChangeableStore: MemoStore {
    var memos: [Memo]

    init(_ memos: [Memo]) { self.memos = memos }

    func list(matching query: String?) -> [Memo] { memos }
    func get(_ id: Memo.ID) -> Memo? { memos.first { $0.id == id } }

    func create(markdown: String) -> Memo {
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
        let model = AppModel(store: store, images: FakeImageStore(), defaults: defaults, editor: FakeEditor())
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
        model.editor.onChanged("Typed here\n")
        await store.replace(memo.id, with: "Changed elsewhere\n")
        model.storeChanged()
        await model.settle()
        #expect(model.current?.markdown == "Typed here\n")
        #expect(await store.get(memo.id)?.markdown == "Typed here\n")
    }

    @Test func aMemoDeletedUnderAnEditComesBackWithTheText() async throws {
        let (model, store, memo) = await model()
        model.editor.onChanged("Typed here\n")
        await store.delete(memo.id)
        model.storeChanged()
        await model.settle()
        #expect(model.current?.markdown == "Typed here\n")
        #expect(model.current?.id != memo.id)
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
}
