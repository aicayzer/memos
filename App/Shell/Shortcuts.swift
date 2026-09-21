import AppKit
import SwiftUI

/// The app's shortcuts in one place: the menus, the palette, the editor's keymap and Settings read it, so
/// they cannot disagree. The keys themselves come from `ShortcutSettings`, which starts from `defaultKeys`.
enum Shortcut: String, CaseIterable, Identifiable {
    case newMemo, duplicate, favorite, browse, back, forward, copyMarkdown, saveAs, find, palette, sidePane
    case heading1, heading2, heading3, paragraph, bold, italic, strikethrough, code, codeBlock, quote
    case bulletList, orderedList, taskList

    var id: String { rawValue }

    /// Editor shortcuts are handled by the web editor, the rest by the app.
    var isEditor: Bool {
        switch self {
        case .newMemo, .duplicate, .favorite, .browse, .back, .forward, .copyMarkdown, .saveAs, .find, .palette, .sidePane:
            false
        default:
            true
        }
    }

    static var app: [Shortcut] { allCases.filter { !$0.isEditor } }
    static var editor: [Shortcut] { allCases.filter(\.isEditor) }

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
        case .palette: "Command Palette"
        case .sidePane: "Show or Hide Side Pane"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .paragraph: "Paragraph"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .code: "Inline Code"
        case .codeBlock: "Code Block"
        case .quote: "Quote"
        case .bulletList: "Bulleted List"
        case .orderedList: "Numbered List"
        case .taskList: "Task List"
        }
    }

    /// The editor's defaults are Milkdown's, so nothing moves for anyone used to them.
    var defaultKeys: [KeyCombo] {
        switch self {
        case .newMemo: [KeyCombo("n", [.command])]
        case .duplicate: [KeyCombo("d", [.command])]
        case .favorite: [KeyCombo("f", [.shift, .command])]
        case .browse: [KeyCombo("p", [.command])]
        case .back: [KeyCombo("[", [.command])]
        case .forward: [KeyCombo("]", [.command])]
        case .copyMarkdown: [KeyCombo("c", [.shift, .command])]
        case .saveAs: [KeyCombo("s", [.shift, .command])]
        case .find: [KeyCombo("f", [.command])]
        case .palette: [KeyCombo("k", [.command])]
        case .sidePane: [KeyCombo("ArrowLeft", [.option, .command]), KeyCombo(".", [.command])]
        case .heading1: [KeyCombo("1", [.option, .command])]
        case .heading2: [KeyCombo("2", [.option, .command])]
        case .heading3: [KeyCombo("3", [.option, .command])]
        case .paragraph: [KeyCombo("0", [.option, .command])]
        case .bold: [KeyCombo("b", [.command])]
        case .italic: [KeyCombo("i", [.command])]
        case .strikethrough: [KeyCombo("x", [.option, .command])]
        case .code: [KeyCombo("e", [.command])]
        case .codeBlock: [KeyCombo("c", [.option, .command])]
        case .quote: [KeyCombo("b", [.shift, .command])]
        case .bulletList: [KeyCombo("l", [.command]), KeyCombo("8", [.option, .command])]
        case .orderedList: [KeyCombo("7", [.option, .command])]
        case .taskList: [KeyCombo("l", [.shift, .command])]
        }
    }
}

/// One key with its modifiers, in the web's key names ("b", "ArrowLeft", "Enter"), which every consumer can be
/// derived from: the menu's key equivalent, the palette's label, ProseMirror's binding and an event to match.
struct KeyCombo: Hashable, Codable, Sendable {
    var key: String
    var modifiers: Modifiers

    struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let command = Modifiers(rawValue: 8)
    }

    init(_ key: String, _ modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The key the event carries, or nil for a bare modifier. Letters are read from the layout without
    /// modifiers, so Option-3 on a British keyboard is the 3 key, and shift is a modifier rather than a case.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if let special = event.specialKey, let name = Self.specialName(special) {
            self.init(name, modifiers)
            return
        }
        switch event.keyCode {
        case 53: self.init("Escape", modifiers)
        case 49: self.init("Space", modifiers)
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased(), character.count == 1,
                  !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            self.init(character, modifiers)
        }
    }

    private static func specialName(_ key: NSEvent.SpecialKey) -> String? {
        switch key {
        case .leftArrow: "ArrowLeft"
        case .rightArrow: "ArrowRight"
        case .upArrow: "ArrowUp"
        case .downArrow: "ArrowDown"
        case .carriageReturn, .enter: "Enter"
        case .tab, .backTab: "Tab"
        case .delete: "Backspace"
        case .deleteForward: "Delete"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "PageUp"
        case .pageDown: "PageDown"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12:
            "F\(key.rawValue - NSEvent.SpecialKey.f1.rawValue + 1)"
        default: nil
        }
    }

    /// A character alone would type; a shortcut needs Command or Control, unless it is a function key.
    var isShortcut: Bool {
        key.hasPrefix("F") && key.count > 1 || !modifiers.isDisjoint(with: [.command, .control])
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

    private static let glyphs: [String: String] = [
        "ArrowLeft": "←", "ArrowRight": "→", "ArrowUp": "↑", "ArrowDown": "↓", "Enter": "↩", "Tab": "⇥",
        "Backspace": "⌫", "Delete": "⌦", "Escape": "⎋", "Space": "␣", "Home": "↖", "End": "↘",
        "PageUp": "⇞", "PageDown": "⇟",
    ]

    private static func glyph(for key: String) -> String {
        glyphs[key] ?? key.uppercased()
    }

    /// For the menu; nil when the key has no key equivalent, which the menu then shows without one.
    var keyboardShortcut: KeyboardShortcut? {
        guard let equivalent = Self.keyEquivalent(for: key) else { return nil }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        return KeyboardShortcut(equivalent, modifiers: eventModifiers)
    }

    private static let keyEquivalents: [String: KeyEquivalent] = [
        "ArrowLeft": .leftArrow, "ArrowRight": .rightArrow, "ArrowUp": .upArrow, "ArrowDown": .downArrow,
        "Enter": .return, "Tab": .tab, "Backspace": .delete, "Delete": .deleteForward, "Escape": .escape,
        "Space": .space, "Home": .home, "End": .end, "PageUp": .pageUp, "PageDown": .pageDown,
    ]

    private static func keyEquivalent(for key: String) -> KeyEquivalent? {
        if let known = keyEquivalents[key] { return known }
        if key.hasPrefix("F"), let number = Int(key.dropFirst()), (1...12).contains(number) {
            // Function keys are the private-use characters AppKit gives them.
            return KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey + number - 1)!))
        }
        return key.count == 1 ? KeyEquivalent(Character(key)) : nil
    }

    /// ProseMirror's name for the binding: "Shift-Mod-b", "Mod-Alt-1", "Mod-ArrowLeft".
    var prosemirror: String {
        var parts: [String] = []
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Alt") }
        if modifiers.contains(.command) { parts.append("Mod") }
        parts.append(key)
        return parts.joined(separator: "-")
    }
}

/// The keys in use, the defaults with the user's changes over them, kept in the defaults as JSON.
@MainActor
@Observable
final class ShortcutSettings {
    private let defaults: UserDefaults
    private var overrides: [String: [KeyCombo]] {
        didSet {
            defaults.set(try? JSONEncoder().encode(overrides), forKey: Self.key)
            onChange?()
        }
    }

    @ObservationIgnored var onChange: (() -> Void)?

    private static let key = "shortcuts"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key)
        overrides = data.flatMap { try? JSONDecoder().decode([String: [KeyCombo]].self, from: $0) } ?? [:]
    }

    func keys(for shortcut: Shortcut) -> [KeyCombo] {
        overrides[shortcut.rawValue] ?? shortcut.defaultKeys
    }

    func setKeys(_ keys: [KeyCombo], for shortcut: Shortcut) {
        if keys == shortcut.defaultKeys {
            overrides[shortcut.rawValue] = nil
        } else {
            overrides[shortcut.rawValue] = keys
        }
    }

    var isDefault: Bool { overrides.isEmpty }

    func reset() {
        overrides = [:]
    }

    /// The first key, for the menu and the palette.
    func first(_ shortcut: Shortcut) -> KeyCombo? { keys(for: shortcut).first }

    func label(_ shortcut: Shortcut) -> String? { first(shortcut)?.label }

    func keyboardShortcut(_ shortcut: Shortcut) -> KeyboardShortcut? { first(shortcut)?.keyboardShortcut }

    /// Keys given to more than one shortcut, each with the others that share it.
    var conflicts: [KeyCombo: [Shortcut]] {
        var owners: [KeyCombo: [Shortcut]] = [:]
        for shortcut in Shortcut.allCases {
            for key in keys(for: shortcut) { owners[key, default: []].append(shortcut) }
        }
        return owners.filter { $0.value.count > 1 }
    }

    /// The app's keys beyond the first of each, which the menu cannot carry, for the window to match.
    var alternates: [(key: KeyCombo, shortcut: Shortcut)] {
        Shortcut.app.flatMap { shortcut in keys(for: shortcut).dropFirst().map { (key: $0, shortcut: shortcut) } }
    }

    /// The editor's bindings, by shortcut name, for the web editor's keymap.
    var editorKeymap: [String: [String]] {
        Dictionary(uniqueKeysWithValues: Shortcut.editor.map { ($0.rawValue, keys(for: $0).map(\.prosemirror)) })
    }
}
