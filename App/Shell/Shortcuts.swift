import AppKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "shortcuts")

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
        case .heading1, .heading2, .heading3, .paragraph, .bold, .italic, .strikethrough, .code, .codeBlock, .quote,
             .bulletList, .orderedList, .taskList:
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

    /// The key the event carries, or nil for a dead key, an unreadable character or a special key the web has
    /// no name for. Letters are read from the layout without modifiers, so Option-3 on a British keyboard is
    /// the 3 key, with shift a modifier rather than a case; shifted punctuation and digits keep their glyph.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if let special = event.specialKey {
            guard let name = Self.specialName(special) else { return nil }
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
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19:
            "F\(key.rawValue - NSEvent.SpecialKey.f1.rawValue + 1)"
        default: nil
        }
    }

    var isFunctionKey: Bool { key.hasPrefix("F") && key.count > 1 }

    /// A character alone would type; a shortcut needs Command or Control, unless it is a function key.
    var isShortcut: Bool {
        isFunctionKey || !modifiers.isDisjoint(with: [.command, .control])
    }

    /// A global hotkey is pressed with no text field in mind, so Option alone will do as well.
    var isHotkey: Bool {
        isFunctionKey || !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }

    /// The menu item this key already triggers, if any: a global hotkey on it would take the key first.
    @MainActor
    func menuItem(in menu: NSMenu) -> NSMenuItem? {
        guard let equivalent = Self.keyEquivalent(for: key).map({ String($0.character) }) else { return nil }
        for item in menu.items {
            if let submenu = item.submenu, let found = menuItem(in: submenu) { return found }
            var itemKey = item.keyEquivalent
            var itemModifiers = item.keyEquivalentModifierMask.intersection([.control, .option, .shift, .command])
            // A capital key equivalent is the menu's other way of saying Shift.
            if itemKey != itemKey.lowercased() {
                itemKey = itemKey.lowercased()
                itemModifiers.insert(.shift)
            }
            if itemKey == equivalent, itemModifiers == modifierFlags { return item }
        }
        return nil
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
        if key.hasPrefix("F"), let number = Int(key.dropFirst()), (1...19).contains(number) {
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
        var stored: [String: [KeyCombo]] = [:]
        if let data = defaults.data(forKey: Self.key) {
            do {
                stored = try JSONDecoder().decode([String: [KeyCombo]].self, from: data)
            } catch {
                log.error("shortcuts unreadable, defaults used: \(error.localizedDescription, privacy: .public)")
            }
        }
        // A shortcut that no longer exists has nothing to show its override on.
        overrides = stored.filter { Shortcut(rawValue: $0.key) != nil }
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

    func isDefault(_ shortcut: Shortcut) -> Bool { overrides[shortcut.rawValue] == nil }

    func reset() {
        overrides = [:]
    }

    func reset(_ shortcut: Shortcut) {
        overrides[shortcut.rawValue] = nil
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

    /// The app's keys beyond the first of each, which the menu cannot carry, for the window to match. A key
    /// some shortcut shows as its first stays with the menu, so what the menu shows is what happens.
    var alternates: [(key: KeyCombo, shortcut: Shortcut)] {
        let shown = Set(Shortcut.allCases.compactMap(first))
        return Shortcut.app.flatMap { shortcut in
            keys(for: shortcut).dropFirst().filter { !shown.contains($0) }.map { (key: $0, shortcut: shortcut) }
        }
    }

    /// The editor's bindings, by shortcut name, for the web editor's keymap.
    var editorKeymap: [String: [String]] {
        Dictionary(uniqueKeysWithValues: Shortcut.editor.map { ($0.rawValue, keys(for: $0).map(\.prosemirror)) })
    }

    /// The Shortcuts tab's lines for these shortcuts: one per key, an empty box for a shortcut without any,
    /// and the box being added, if it belongs to one of them, where its key will go.
    func rows(for shortcuts: [Shortcut], adding: ShortcutRow? = nil) -> [ShortcutRow] {
        shortcuts.flatMap { shortcut -> [ShortcutRow] in
            let keys = keys(for: shortcut)
            guard !keys.isEmpty else { return [ShortcutRow(shortcut: shortcut, index: 0, key: nil)] }
            var rows = keys.enumerated().map { ShortcutRow(shortcut: shortcut, index: $0.offset, key: $0.element) }
            if let adding, adding.shortcut == shortcut {
                rows.insert(adding, at: min(adding.index, rows.count))
            }
            return rows
        }
    }

    /// Takes a typed key for the row: in place of its own, or into the place an empty box holds. Should the
    /// row's key have moved from under the box, the typed key still lands, at the end.
    func record(_ key: KeyCombo, in row: ShortcutRow) {
        var keys = keys(for: row.shortcut)
        if row.key == nil {
            keys.insert(key, at: min(row.index, keys.count))
        } else if keys.indices.contains(row.index), keys[row.index] == row.key {
            keys[row.index] = key
        } else {
            keys.append(key)
        }
        setKeys(keys, for: row.shortcut)
    }

    /// Removes the row's key, if it is still where the row had it.
    func clear(_ row: ShortcutRow) {
        var keys = keys(for: row.shortcut)
        guard let key = row.key, keys.indices.contains(row.index), keys[row.index] == key else { return }
        keys.remove(at: row.index)
        setKeys(keys, for: row.shortcut)
    }
}

/// One line of the Shortcuts tab: a key of a shortcut, or the empty box a key is typed into.
struct ShortcutRow: Identifiable {
    let shortcut: Shortcut
    /// The key's place among the shortcut's keys, or the place a typed one will take.
    let index: Int
    let key: KeyCombo?
    /// A box put below a key to type another one into.
    var isAdded = false

    /// Distinct per shortcut and per key, so the grouped form never shows one line's title on another.
    var id: String { "\(shortcut.rawValue)-\(isAdded ? "added" : String(index))" }

    /// The first line carries the shortcut's title.
    var isFirst: Bool { index == 0 }
}
