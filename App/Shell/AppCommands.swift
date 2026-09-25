import SwiftUI

struct AppCommands: Commands {
    @Bindable var model: AppModel
    let textPad: TextPad
    let updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if updater.isAvailable {
                Button("Check for Updates…") { updater.check() }
                    .disabled(!updater.canCheck)
            }
        }
        CommandGroup(replacing: .newItem) {
            if textPad.isActive {
                Button("New TextPad") { textPad.commandNew() }
                    .keyboardShortcut("n", modifiers: .command)
            } else {
                item(.newMemo)
            }
            if !textPad.isActive {
                Button("New TextPad") { textPad.newFile() }
                    .disabled(!textPad.enabled)
            }
            Button("Open Text File…") { Task { await textPad.openPicker() } }
                .disabled(!textPad.enabled)
            item(.duplicate)
            item(.delete)
            item(.favorite, title: model.current?.favorite == true ? "Unfavorite Memo" : "Favorite Memo")
            Divider()
            item(.browse)
            item(.back).disabled(!model.history.canGoBack)
            item(.forward).disabled(!model.history.canGoForward)
            Divider()
            item(.copyMarkdown)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                if textPad.isActive { textPad.save() }
                else { Task { _ = await model.flush() } }
            }
            .keyboardShortcut("s", modifiers: .command)
        }
        CommandGroup(after: .saveItem) {
            Divider()
            if textPad.isActive {
                Button("Save As…") { Task { await textPad.saveAs() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Share…") { textPad.share() }
                Button("Save to Memos") { Task { await textPad.saveToMemos() } }
            } else {
                item(.saveAs)
                Button("Share…") { Task { await model.share() } }
            }
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            item(.find)
        }
        // The editor handles its own keys first; these items are the same actions by mouse, and where the keys show.
        CommandMenu("Format") {
            item(.heading1)
            item(.heading2)
            item(.heading3)
            item(.paragraph)
            Divider()
            item(.bold)
            item(.italic)
            item(.strikethrough)
            item(.code)
            Divider()
            item(.codeBlock)
            item(.quote)
            Divider()
            item(.bulletList)
            item(.orderedList)
            item(.taskList)
        }
        // Replacing drops Show/Hide Toolbar, which would collapse the title bar the top row is drawn in.
        CommandGroup(replacing: .toolbar) {
            item(.palette)
            Toggle("Formatting Bar", isOn: Binding(get: { !model.formatBarHidden }, set: { model.formatBarHidden = !$0 }))
            item(.sidePane, title: model.sidePane ? "Hide Side Pane" : "Show Side Pane")
        }
        CommandGroup(before: .windowArrangement) {
            Toggle("Always on Top", isOn: $model.floating)
            Divider()
        }
    }

    /// A menu item carries the shortcut's first key; the window matches the others.
    private func item(_ shortcut: Shortcut, title: String? = nil) -> some View {
        Button(title ?? shortcut.title) { model.perform(shortcut) }
            .keyboardShortcut(model.shortcuts.keyboardShortcut(shortcut))
            .disabled(textPad.isActive)
    }
}
