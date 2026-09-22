import Foundation
import Testing
@testable import Memos

@MainActor
@Suite struct ModelTests {
    private func model(_ markdown: String...) async -> (AppModel, ChangeableStore, FakeEditor) {
        let memos = markdown.map { Memo(id: UUID(), markdown: $0, favorite: false, createdAt: .now, updatedAt: .now) }
        let store = ChangeableStore(memos)
        let defaults = UserDefaults(suiteName: "model-tests")!
        defaults.removePersistentDomain(forName: "model-tests")
        let editor = FakeEditor()
        let model = AppModel(store: store, images: FakeImageStore(), defaults: defaults, editor: editor)
        await model.start()
        return (model, store, editor)
    }

    @Test func dismissingFindClearsTheSearch() async {
        let (model, _, editor) = await model("A memo")
        model.overlay = .find
        model.findText = "memo"
        model.find()
        model.dismissOverlay()
        #expect(editor.searches == ["memo", ""])
        #expect(model.findText.isEmpty)
    }

    @Test func replacingFindWithAnotherOverlayClearsTheSearch() async {
        let (model, _, editor) = await model("A memo")
        model.overlay = .find
        model.findText = "memo"
        model.find()
        model.overlay = .browse
        #expect(editor.searches.last == "")
        #expect(model.findText.isEmpty)
    }

    @Test func erasingTheQueryClearsTheSearch() async {
        let (model, _, editor) = await model("A memo")
        model.overlay = .find
        model.findText = "memo"
        model.find()
        model.findText = ""
        model.find()
        #expect(editor.searches == ["memo", ""])
    }

    @Test func switchingMemosWritesTheOneBeingLeft() async throws {
        let (model, store, editor) = await model("First\n", "Second\n")
        let first = try #require(model.current)
        let second = try #require(await store.list(matching: nil).first { $0.id != first.id })
        editor.type("First, edited\n")
        await model.open(second.id)
        #expect(await store.get(first.id)?.markdown == "First, edited\n")
        #expect(editor.text == "Second\n")
    }

    @Test func quittingWritesWhatIsOnScreen() async throws {
        let (model, store, editor) = await model("A memo\n")
        let memo = try #require(model.current)
        editor.type("A memo, edited\n")
        #expect(await model.flush())
        #expect(await store.get(memo.id)?.markdown == "A memo, edited\n")
    }

    @Test func goingBackAndForwardReturnsToTheSameMemos() async throws {
        let (model, store, _) = await model("First\n")
        let first = try #require(model.current)
        let second = try await store.create(markdown: "Second\n")
        await model.open(second.id)
        #expect(model.history.canGoBack)
        await model.goBack()
        #expect(model.current?.id == first.id)
        #expect(model.history.canGoForward)
        await model.goForward()
        #expect(model.current?.id == second.id)
    }

    @Test func duplicatingOpensACopy() async throws {
        let (model, store, _) = await model("A memo\n")
        let original = try #require(model.current)
        await model.duplicate()
        #expect(model.current?.id != original.id)
        #expect(model.current?.markdown == "A memo\n")
        #expect(await store.list(matching: nil).count == 2)
    }

    @Test func favoritingKeepsTheTextBeingEdited() async throws {
        let (model, _, editor) = await model("A memo\n")
        editor.type("A memo, edited\n")
        await model.toggleFavorite()
        #expect(model.current?.favorite == true)
        #expect(model.current?.markdown == "A memo, edited\n")
    }

    @Test func deletingShowsTheMemoThatFollowed() async throws {
        let (model, store, _) = await model("Oldest\n")
        let second = try await store.create(markdown: "Middle\n")
        _ = try await store.create(markdown: "Newest\n")
        await model.open(second.id)
        await model.delete(second)
        let remaining = try await store.list(matching: nil)
        #expect(remaining.count == 2)
        #expect(model.current?.markdown == "Oldest\n")
        #expect(!model.history.canGoBack)
    }

    @Test func deletingTheLastMemoLeavesAnEmptyOne() async throws {
        let (model, store, _) = await model("Only one\n")
        let only = try #require(model.current)
        await model.delete(only)
        #expect(model.current?.id != only.id)
        #expect(model.current?.markdown == "")
        #expect(await store.list(matching: nil).count == 1)
    }

    @Test func deletingTakesTheImagesNoOneElseRefersTo() async throws {
        let store = ChangeableStore([])
        let images = FakeImageStore()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
        let kept = try await images.save(png)
        let defaults = UserDefaults(suiteName: "model-tests")!
        defaults.removePersistentDomain(forName: "model-tests")
        let memo = try await store.create(markdown: "![](\(kept.path))\n")
        let model = AppModel(store: store, images: images, defaults: defaults, editor: FakeEditor())
        await model.start()
        #expect(await images.held.count == 1)
        await model.delete(memo)
        #expect(await images.held.isEmpty)
    }

    @Test func anEditReportedForAnEarlierMemoIsDropped() async {
        let editor = EditorController(images: FakeImageStore())
        var reported: [String] = []
        editor.onChanged = { reported.append($0) }
        editor.receive(.ready)
        editor.load("First\n")
        editor.load("Second\n")
        editor.receive(.changed("late edit to the first", generation: 1))
        #expect(reported.isEmpty)
        editor.receive(.changed("an edit to the second", generation: 2))
        #expect(reported == ["an edit to the second"])
    }
}
