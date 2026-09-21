import AppKit
import SwiftUI

/// The app's shortcuts in one place: the menus, the palette and Settings read it, so they cannot disagree.
enum Shortcut: String, CaseIterable, Identifiable {
    case newMemo, duplicate, favorite, browse, back, forward, copyMarkdown, saveAs, find
    case bulletList, taskList, palette, sidePane

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newMemo: "New Memo"
        case .duplicate: "Duplicate Memo"
        case .favorite: "Favorite or Unfavorite Memo"
        case .browse: "Browse Memos"
        case .back: "Go Back"
        case .forward: "Go Forward"
        case .copyMarkdown: "Copy as Markdown"
        case .saveAs: "Save As…"
        case .find: "Find in Memo"
        case .bulletList: "Bulleted List"
        case .taskList: "Task List"
        case .palette: "Command Palette"
        case .sidePane: "Show or Hide Side Pane"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .newMemo: "n"
        case .duplicate: "d"
        case .favorite, .find: "f"
        case .browse: "p"
        case .back: "["
        case .forward: "]"
        case .copyMarkdown: "c"
        case .saveAs: "s"
        case .bulletList, .taskList: "l"
        case .palette: "k"
        case .sidePane: .leftArrow
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .favorite, .copyMarkdown, .saveAs, .taskList: [.command, .shift]
        case .sidePane: [.command, .option]
        default: .command
        }
    }

    var keyboardShortcut: KeyboardShortcut { KeyboardShortcut(key, modifiers: modifiers) }

    /// A second key for the same action. A menu item carries one key, so the window takes this one.
    var alternate: (key: String, modifiers: NSEvent.ModifierFlags, label: String)? {
        switch self {
        case .sidePane: (".", .command, "⌘.")
        default: nil
        }
    }

    /// As the palette and Settings show it, modifiers in the system's order.
    var label: String {
        var label = ""
        if modifiers.contains(.control) { label += "⌃" }
        if modifiers.contains(.option) { label += "⌥" }
        if modifiers.contains(.shift) { label += "⇧" }
        if modifiers.contains(.command) { label += "⌘" }
        return label + Self.glyph(for: key)
    }

    private static func glyph(for key: KeyEquivalent) -> String {
        switch key {
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        default: String(key.character).uppercased()
        }
    }

    /// The editor's own keys, which it handles before the app sees them. They are Milkdown's, set in the web
    /// editor, so this restates them for Settings.
    static let editor: [(title: String, label: String)] = [
        ("Bold", "⌘B"),
        ("Italic", "⌘I"),
        ("Strikethrough", "⌥⌘X"),
        ("Inline Code", "⌘E"),
        ("Heading 1 to 6", "⌥⌘1 to ⌥⌘6"),
        ("Paragraph", "⌥⌘0"),
        ("Quote", "⇧⌘B"),
        ("Code Block", "⌥⌘C"),
        ("Bulleted List", "⌥⌘8"),
        ("Numbered List", "⌥⌘7"),
        ("Indent List Item", "⇥"),
        ("Outdent List Item", "⇧⇥"),
        ("Line Break", "⇧↩"),
        ("Undo", "⌘Z"),
        ("Redo", "⇧⌘Z"),
    ]
}
