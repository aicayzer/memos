import AppIntents
import AppKit
import Foundation

struct NewMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "New Memo"
    static let description = IntentDescription("Makes a memo from the text given.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("New memo saying \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<MemoEntity> {
        let store = try MemoIntents.store()
        let memo = try await store.create(markdown: text.hasSuffix("\n") ? text : text + "\n")
        return .result(value: MemoEntity(memo))
    }
}

struct AppendToMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Append to Memo"
    static let description = IntentDescription("Adds text to the end of a memo, as a paragraph of its own.")

    @Parameter(title: "Memo") var memo: MemoEntity
    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true)) var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to \(\.$memo)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<MemoEntity> {
        let store = try MemoIntents.store()
        let found = try await MemoIntents.memo(memo, in: store)
        let saved = try await store.update(found.id, markdown: Memo.appending(text, to: found.markdown))
        return .result(value: MemoEntity(saved))
    }
}

struct OpenMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Memo"
    static let description = IntentDescription("Shows a memo in the window.")
    static let openAppWhenRun = true

    @Parameter(title: "Memo") var memo: MemoEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$memo)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let id = memo.id
        if let delegate = NSApp.delegate as? AppDelegate {
            await delegate.model.open(id)
        }
        return .result()
    }
}

struct SearchMemosIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Memos"
    static let description = IntentDescription("Finds the memos whose title or text match.")

    @Parameter(title: "Query") var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find memos matching \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[MemoEntity]> {
        let memos = try await MemoIntents.store().list(matching: query)
        return .result(value: memos.map(MemoEntity.init))
    }
}

struct FavoriteMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Favorite Memo"
    static let description = IntentDescription("Marks a memo as a favorite, so it sorts first.")

    @Parameter(title: "Memo") var memo: MemoEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Favorite \(\.$memo)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<MemoEntity> {
        let store = try MemoIntents.store()
        return .result(value: MemoEntity(try await store.setFavorite(memo.id, true)))
    }
}

struct UnfavoriteMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Unfavorite Memo"
    static let description = IntentDescription("Takes a memo off the favorites.")

    @Parameter(title: "Memo") var memo: MemoEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Unfavorite \(\.$memo)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<MemoEntity> {
        let store = try MemoIntents.store()
        return .result(value: MemoEntity(try await store.setFavorite(memo.id, false)))
    }
}

struct DeleteMemoIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete Memo"
    static let description = IntentDescription("Deletes a memo. There is no undo.")

    @Parameter(title: "Memo") var memo: MemoEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$memo)")
    }

    func perform() async throws -> some IntentResult {
        let store = try MemoIntents.store()
        let found = try await MemoIntents.memo(memo, in: store)
        // The framework has no name for deleting, so the question carries it.
        try await requestConfirmation(
            dialog: IntentDialog("Delete \u{201C}\(found.title)\u{201D}? The memo is gone for good.")
        )
        try await store.delete(found.id)
        await ImageSweep.run(store: store, images: FolderImageStore(besideStoreAt: store.fileURL))
        return .result()
    }
}

struct MemosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewMemoIntent(),
            phrases: ["New memo in \(.applicationName)", "Make a \(.applicationName)"],
            shortTitle: "New Memo",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: SearchMemosIntent(),
            phrases: ["Search \(.applicationName)", "Find a memo in \(.applicationName)"],
            shortTitle: "Search Memos",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenMemoIntent(),
            phrases: ["Open a memo in \(.applicationName)"],
            shortTitle: "Open Memo",
            systemImageName: "doc.text"
        )
    }
}
