import AppKit
import Foundation
@testable import Memos

/// A fresh folder in the temporary directory; pair it with `discard` so a run leaves nothing behind.
func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

func discard(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// The editor without a window: what the app put on screen, and what the reader typed back.
@MainActor
final class FakeEditor: Editing {
    var caret = CaretState()
    var allowsFocus = true
    var documentID = ""
    private(set) var focusCount = 0
    var onChanged: (String) -> Void = { _ in }
    var onOpenLink: (URL) -> Void = { _ in }
    var onCopy: (String) -> Void = { _ in }
    var onWarning: (String) -> Void = { _ in }
    var onDropFiles: ([URL], CGPoint) -> Void = { _, _ in }
    var accentOverride: NSColor?
    var textSize = TextSize.medium.points
    var keymap: [String: [String]] = [:]
    let contentView = NSView()

    private(set) var text = ""
    private(set) var loaded: [String] = []
    private(set) var reloaded: [String] = []
    private(set) var inserted: [ImageReference] = []

    /// An edit in the window, reported as the editor reports one.
    func typeWithoutReporting(_ markdown: String) { text = markdown }

    func type(_ markdown: String) {
        text = markdown
        onChanged(markdown)
    }

    func load(_ markdown: String) {
        text = markdown
        loaded.append(markdown)
    }

    func reload(_ markdown: String) {
        text = markdown
        reloaded.append(markdown)
    }

    func format(_ command: FormatCommand, argument: String?) {}
    func focus() { if allowsFocus { focusCount += 1 } }
    private(set) var searches: [String] = []
    func find(_ text: String) { searches.append(text) }
    func insertPaths(_ paths: [String], at point: CGPoint) {}

    func insertImages(_ references: [ImageReference], at point: CGPoint?) {
        inserted.append(contentsOf: references)
    }

    var snapshotError: (any Error)?
    func snapshot() async throws -> String {
        if let snapshotError { throw snapshotError }
        return text
    }
    func table(_ command: String) {}
    func pasteAsPlainText(_ value: String) { type(text + value) }
}

/// Images in memory, so a test needs no folder.
actor FakeImageStore: ImageStore {
    private(set) var held: [String: Data] = [:]

    func save(_ data: Data) throws -> ImageReference {
        guard let type = ImageType(sniffing: data) else { throw ImageStoreError.unsupported }
        let path = "\(ImageReference.folder)/\(String(format: "%064x", data.count)).\(type.fileExtension)"
        held[path] = data
        return ImageReference(path: path)
    }

    func url(for path: String) -> URL? { nil }

    func removeOrphans(keeping used: Set<String>) {
        held = held.filter { used.contains($0.key) }
    }
}
