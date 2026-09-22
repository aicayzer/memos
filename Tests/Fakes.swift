import AppKit
import Foundation
@testable import Memos

/// The editor without a window: what the app put on screen, and what the reader typed back.
@MainActor
final class FakeEditor: Editing {
    var caret = CaretState()
    var onChanged: (String) -> Void = { _ in }
    var onOpenLink: (URL) -> Void = { _ in }
    var onCopy: (String) -> Void = { _ in }
    var onDropFiles: ([URL], CGPoint) -> Void = { _, _ in }
    var onPasteImage: () -> Void = {}
    var accentOverride: NSColor?
    var textSize = TextSize.medium.points
    var keymap: [String: [String]] = [:]
    let contentView = NSView()

    private(set) var text = ""
    private(set) var loaded: [String] = []
    private(set) var reloaded: [String] = []
    private(set) var inserted: [ImageReference] = []
    private var edited = false

    /// An edit in the window, reported as the editor reports one.
    func type(_ markdown: String) {
        text = markdown
        edited = true
        onChanged(markdown)
    }

    func load(_ markdown: String) {
        text = markdown
        edited = false
        loaded.append(markdown)
    }

    func reload(_ markdown: String) {
        text = markdown
        edited = false
        reloaded.append(markdown)
    }

    func format(_ command: FormatCommand, argument: String?) {}
    func focus() {}
    private(set) var searches: [String] = []
    func find(_ text: String) { searches.append(text) }
    func insertPaths(_ paths: [String], at point: CGPoint) {}

    func insertImages(_ references: [ImageReference], at point: CGPoint?) {
        inserted.append(contentsOf: references)
    }

    func markdown() async -> String? { edited ? text : nil }
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
