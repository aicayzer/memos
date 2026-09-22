import AppKit
import ArgumentParser
import Foundation

@main
struct MemosCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memos",
        abstract: "Memos from the shell: the same memos the app shows, read and written in place.",
        discussion: "MEMOS_STORE in the environment points the tool at another store file.",
        subcommands: [
            List.self, Show.self, New.self, Append.self, Replace.self, Edit.self,
            Favorite.self, Unfavorite.self, Delete.self, Open.self, Path.self,
        ],
        defaultSubcommand: List.self
    )
}

/// A memo as the commands name it.
struct Reference: ExpressibleByArgument {
    let text: String
    init?(argument: String) { text = argument }

    static let help = ArgumentHelp("A memo: its id, the start of one (4 or more characters), its title, or the start of that.")
}

struct ToolError: Error, CustomStringConvertible {
    let description: String
}

/// The CLI is not sandboxed. It follows the shared path but cannot resolve a bookmark issued to the app.
enum Shared {
    static func store() throws -> LibraryStore {
        if let path = ProcessInfo.processInfo.environment["MEMOS_STORE"], !path.isEmpty { return LibraryStore(fileURL: URL(fileURLWithPath: path), useSecurityScope: false) }
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "MemosAppIdentifier") as? String else {
            throw ToolError(description: "the tool was built without the app's identifier")
        }
        let container = URL.homeDirectory.appending(path: "Library/Containers/\(identifier)/Data/Library/Application Support")
        guard FileManager.default.fileExists(atPath: container.path) else {
            throw ToolError(description: "Memos has not run yet; open it once first")
        }
        return LibraryStore(fileURL: container.appending(path: "store.json"), useSecurityScope: false)
    }

    /// The memos' images, in the folder beside the store file.
    static func images(for store: LibraryStore) -> LibraryStore { store }

    static func find(_ reference: Reference, in store: LibraryStore) async throws -> Memo {
        do {
            return try MemoLookup.find(reference.text, in: try await store.list(matching: nil))
        } catch MemoLookup.Failure.none(let text) {
            throw ToolError(description: "no memo matches \"\(text)\"")
        } catch MemoLookup.Failure.several(let text, let memos) {
            let names = memos.map { "  \($0.id.uuidString.prefix(8).lowercased())  \($0.title)" }.joined(separator: "\n")
            throw ToolError(description: "\"\(text)\" matches several memos:\n\(names)")
        }
    }

    /// The arguments as one text, or standard input when there are none and it is not the keyboard.
    static func text(_ words: [String]) throws -> String {
        if !words.isEmpty { return words.joined(separator: " ") }
        guard isatty(STDIN_FILENO) == 0, let data = try FileHandle.standardInput.readToEnd(), !data.isEmpty else {
            throw ToolError(description: "nothing to add: give text, or pipe it in")
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func line(_ memo: Memo) -> String {
        let star = memo.favorite ? "*" : " "
        let when = memo.updatedAt.formatted(.relative(presentation: .named))
        return "\(memo.id.uuidString.prefix(8).lowercased()) \(star) \(memo.title.padding(toLength: 40, withPad: " ", startingAt: 0))  \(when)"
    }

    static func json(_ memos: [Memo]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(memos), as: UTF8.self)
    }
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List memos, favorites first then newest; a query narrows them.")

    @Argument(help: "Text to look for in titles and bodies.") var query: String?
    @Flag(name: .long, help: "Every field, as JSON.") var json = false

    func run() async throws {
        let memos = try await Shared.store().list(matching: query)
        if json {
            print(try Shared.json(memos))
        } else {
            for memo in memos { print(Shared.line(memo)) }
        }
    }
}

struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print a memo's markdown.")

    @Argument(help: Reference.help) var memo: Reference
    @Flag(name: .long, help: "Every field, as JSON.") var json = false

    func run() async throws {
        let store = try Shared.store()
        let found = try await Shared.find(memo, in: store)
        print(json ? try Shared.json([found]) : found.markdown, terminator: found.markdown.hasSuffix("\n") && !json ? "" : "\n")
    }
}

struct New: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Make a memo from the text given, or from standard input.")

    @Argument(help: "The memo's text.") var text: [String] = []

    func run() async throws {
        let memo = try await Shared.store().create(markdown: try Shared.text(text))
        print(memo.id.uuidString.lowercased())
    }
}

struct Append: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add text to the end of a memo, as a paragraph of its own.")

    @Argument(help: Reference.help) var memo: Reference
    @Argument(help: "The text to add.") var text: [String] = []

    func run() async throws {
        let store = try Shared.store()
        let found = try await Shared.find(memo, in: store)
        _ = try await store.update(found.id, markdown: Memo.appending(try Shared.text(text), to: found.markdown), expecting: found.markdown)
    }
}

struct Replace: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Replace a memo's text with standard input.")

    @Argument(help: Reference.help) var memo: Reference

    func run() async throws {
        let store = try Shared.store()
        let found = try await Shared.find(memo, in: store)
        _ = try await store.update(found.id, markdown: try Shared.text([]), expecting: found.markdown)
    }
}

struct Edit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open a memo in $EDITOR and save what comes back.")

    @Argument(help: Reference.help) var memo: Reference

    func run() async throws {
        let store = try Shared.store()
        let found = try await Shared.find(memo, in: store)
        // Its own folder, so two edits of one title do not share a file.
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: Memo.fileName(for: found.title))
        try found.markdown.write(to: file, atomically: true, encoding: .utf8)
        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(editor) \"$1\"", "--", file.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ToolError(description: "\(editor) exited with \(process.terminationStatus); nothing saved") }
        let edited = try String(contentsOf: file, encoding: .utf8)
        if edited != found.markdown { _ = try await store.update(found.id, markdown: edited, expecting: found.markdown) }
    }
}

struct Favorite: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Mark a memo as a favorite.")

    @Argument(help: Reference.help) var memo: Reference

    func run() async throws {
        let store = try Shared.store()
        _ = try await store.setFavorite(try await Shared.find(memo, in: store).id, true)
    }
}

struct Unfavorite: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Take a memo off the favorites.")

    @Argument(help: Reference.help) var memo: Reference

    func run() async throws {
        let store = try Shared.store()
        _ = try await store.setFavorite(try await Shared.find(memo, in: store).id, false)
    }
}

struct Delete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a memo. There is no undo.")

    @Argument(help: Reference.help) var memo: Reference

    func run() async throws {
        let store = try Shared.store()
        let found = try await Shared.find(memo, in: store)
        try await store.delete(found.id)
        // The app sweeps too; whichever deletes a memo takes its images with it.
        await ImageSweep.run(store: store, images: Shared.images(for: store))
        print("deleted \(found.title)")
    }
}

struct Open: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the app, on a memo when one is named.")

    @Argument(help: Reference.help) var memo: Reference?

    func run() async throws {
        var url = URLComponents()
        url.scheme = "memos"
        if let memo {
            let found = try await Shared.find(memo, in: try Shared.store())
            url.host = "memo"
            url.path = "/\(found.id.uuidString.lowercased())"
        }
        guard NSWorkspace.shared.open(url.url!) else { throw ToolError(description: "Memos is not registered to open memos:// links; open the app once") }
    }
}

struct Path: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print where the store file is.")

    func run() async throws {
        print(try await Shared.store().status().location.path)
    }
}
