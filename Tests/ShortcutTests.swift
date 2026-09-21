import AppKit
import SwiftUI
import Testing
@testable import Memos

@Suite struct KeyComboTests {
    private func event(_ characters: String, ignoring: String? = nil, flags: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: ignoring ?? characters, isARepeat: false, keyCode: keyCode
        )!
    }

    @Test func eventsReadAsKeys() {
        #expect(KeyCombo(event: event("n", flags: [.command])) == KeyCombo("n", [.command]))
        #expect(KeyCombo(event: event("F", ignoring: "F", flags: [.shift, .command])) == KeyCombo("f", [.shift, .command]))
        // Option-3 on a British keyboard types a hash; the shortcut is the 3 key.
        #expect(KeyCombo(event: event("#", ignoring: "3", flags: [.option, .command])) == KeyCombo("3", [.option, .command]))
        #expect(KeyCombo(event: event("\u{F702}", flags: [.option, .command])) == KeyCombo("ArrowLeft", [.option, .command]))
        #expect(KeyCombo(event: event("\r")) == KeyCombo("Enter", []))
        #expect(KeyCombo(event: event("\u{7F}")) == KeyCombo("Backspace", []))
        #expect(KeyCombo(event: event("\u{F708}")) == KeyCombo("F5", []))
        #expect(KeyCombo(event: event("\u{1B}", keyCode: 53)) == KeyCombo("Escape", []))
        #expect(KeyCombo(event: event(" ", keyCode: 49)) == KeyCombo("Space", []))
        // A caps-lock or function flag is not part of a shortcut.
        #expect(KeyCombo(event: event("n", flags: [.command, .capsLock, .function])) == KeyCombo("n", [.command]))
        #expect(KeyCombo(event: event("\u{F710}", flags: [.command])) == KeyCombo("F13", [.command]))
        // A special key the web has no name for, such as Insert, is not a shortcut at all.
        #expect(KeyCombo(event: event("\u{F727}", flags: [.command])) == nil)
    }

    @Test func onlyChordsAndFunctionKeysAreShortcuts() {
        #expect(KeyCombo("n", [.command]).isShortcut)
        #expect(KeyCombo("n", [.control]).isShortcut)
        #expect(KeyCombo("F5", []).isShortcut)
        #expect(!KeyCombo("n", []).isShortcut)
        #expect(!KeyCombo("n", [.shift]).isShortcut)
        #expect(!KeyCombo("n", [.option]).isShortcut)
    }

    @Test func labelsFollowTheSystemOrder() {
        #expect(KeyCombo("f", [.shift, .command]).label == "⇧⌘F")
        #expect(KeyCombo("ArrowLeft", [.option, .command]).label == "⌥⌘←")
        #expect(KeyCombo("n", [.control, .option, .shift, .command]).label == "⌃⌥⇧⌘N")
        #expect(KeyCombo("Enter", [.command]).label == "⌘↩")
        #expect(KeyCombo("F5", []).label == "F5")
    }

    @Test func prosemirrorNames() {
        #expect(KeyCombo("b", [.command]).prosemirror == "Mod-b")
        #expect(KeyCombo("2", [.option, .command]).prosemirror == "Alt-Mod-2")
        #expect(KeyCombo("b", [.shift, .command]).prosemirror == "Shift-Mod-b")
        #expect(KeyCombo("ArrowLeft", [.control]).prosemirror == "Ctrl-ArrowLeft")
    }

    @Test func menuKeyEquivalents() {
        #expect(KeyCombo("n", [.command]).keyboardShortcut == KeyboardShortcut("n"))
        #expect(KeyCombo("ArrowLeft", [.option, .command]).keyboardShortcut == KeyboardShortcut(.leftArrow, modifiers: [.option, .command]))
        #expect(KeyCombo("F5", []).keyboardShortcut?.key.character == Character(UnicodeScalar(NSF5FunctionKey)!))
        #expect(KeyCombo("Unknown", [.command]).keyboardShortcut == nil)
    }

    @Test func combosRoundTripAsJSON() throws {
        let keys = [KeyCombo("ArrowLeft", [.option, .command]), KeyCombo(".", [.command])]
        let data = try JSONEncoder().encode(keys)
        #expect(try JSONDecoder().decode([KeyCombo].self, from: data) == keys)
    }
}

@MainActor
@Suite struct ShortcutSettingsTests {
    private func settings() -> (ShortcutSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: "shortcut-tests")!
        defaults.removePersistentDomain(forName: "shortcut-tests")
        return (ShortcutSettings(defaults: defaults), defaults)
    }

    @Test func defaultsUntilChanged() {
        let (settings, _) = settings()
        #expect(settings.isDefault)
        #expect(settings.keys(for: .newMemo) == [KeyCombo("n", [.command])])
        #expect(settings.label(.sidePane) == "⌥⌘←")
        #expect(settings.alternates.map(\.key) == [KeyCombo(".", [.command])])
    }

    @Test func changesPersistAndDefaultsClear() {
        let (settings, defaults) = settings()
        settings.setKeys([KeyCombo("m", [.command]), KeyCombo("F2", [])], for: .newMemo)
        #expect(!settings.isDefault)
        #expect(settings.keyboardShortcut(.newMemo) == KeyboardShortcut("m"))
        #expect(settings.alternates.contains { $0.key == KeyCombo("F2", []) && $0.shortcut == .newMemo })
        let reopened = ShortcutSettings(defaults: defaults)
        #expect(reopened.keys(for: .newMemo) == [KeyCombo("m", [.command]), KeyCombo("F2", [])])
        // Setting the defaults back is the same as never having changed them.
        reopened.setKeys(Shortcut.newMemo.defaultKeys, for: .newMemo)
        #expect(reopened.isDefault)
    }

    @Test func aShortcutCanHaveNoKey() {
        let (settings, _) = settings()
        settings.setKeys([], for: .duplicate)
        #expect(settings.keys(for: .duplicate).isEmpty)
        #expect(settings.keyboardShortcut(.duplicate) == nil)
        #expect(settings.label(.duplicate) == nil)
        settings.reset()
        #expect(settings.keys(for: .duplicate) == Shortcut.duplicate.defaultKeys)
    }

    @Test func anAlternateNeverTakesAShownKey() {
        let (settings, _) = settings()
        // ⌘F shows on Find in Memo; as a second key of New Memo it would take the menu's key first.
        settings.setKeys([KeyCombo("m", [.command]), KeyCombo("f", [.command])], for: .newMemo)
        #expect(!settings.alternates.contains { $0.key == KeyCombo("f", [.command]) })
        #expect(settings.conflicts[KeyCombo("f", [.command])] == [.newMemo, .find])
    }

    @Test func unknownAndUnreadableOverridesAreDropped() {
        let defaults = UserDefaults(suiteName: "shortcut-tests")!
        defaults.removePersistentDomain(forName: "shortcut-tests")
        defaults.set(Data("{\"gone\": [], \"newMemo\": [{\"key\": \"m\", \"modifiers\": 8}]}".utf8), forKey: "shortcuts")
        let settings = ShortcutSettings(defaults: defaults)
        #expect(settings.keys(for: .newMemo) == [KeyCombo("m", [.command])])
        #expect(!settings.isDefault)
        settings.setKeys(Shortcut.newMemo.defaultKeys, for: .newMemo)
        #expect(settings.isDefault)
        defaults.set(Data("nonsense".utf8), forKey: "shortcuts")
        #expect(ShortcutSettings(defaults: defaults).isDefault)
    }

    @Test func conflictsNameEveryOwner() {
        let (settings, _) = settings()
        #expect(settings.conflicts.isEmpty)
        settings.setKeys([KeyCombo("n", [.command])], for: .bold)
        #expect(settings.conflicts[KeyCombo("n", [.command])] == [.newMemo, .bold])
    }

    @Test func editorKeymapCoversEveryEditorShortcut() {
        let (settings, _) = settings()
        let keymap = settings.editorKeymap
        #expect(Set(keymap.keys) == Set(Shortcut.editor.map(\.rawValue)))
        #expect(keymap["bulletList"] == ["Mod-l", "Alt-Mod-8"])
        #expect(keymap["newMemo"] == nil)
    }
}
