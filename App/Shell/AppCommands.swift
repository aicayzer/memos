import SwiftUI

struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Memo") { Task { await model.newMemo() } }
                .keyboardShortcut("n")
            Button("Duplicate Memo") { Task { await model.duplicate() } }
                .keyboardShortcut("d")
            Button(model.current?.favorite == true ? "Unfavorite Memo" : "Favorite Memo") { Task { await model.toggleFavorite() } }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("Browse Memos") { model.toggle(.browse) }
                .keyboardShortcut("p")
            Button("Go Back") { Task { await model.goBack() } }
                .keyboardShortcut("[")
                .disabled(!model.history.canGoBack)
            Button("Go Forward") { Task { await model.goForward() } }
                .keyboardShortcut("]")
                .disabled(!model.history.canGoForward)
            Divider()
            Button("Copy as Markdown") { model.copyAsMarkdown() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Save As…") { Task { await model.saveAs() } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Share…") { Task { await model.share() } }
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find in Memo") { model.toggle(.find) }
                .keyboardShortcut("f")
        }
        // The editor's own keys (⌘B, ⌘I) reach the web view first; these are the ones it does not have.
        CommandMenu("Format") {
            Button("Bulleted List") { model.editor.format(.bulletList) }
                .keyboardShortcut("l")
            Button("Task List") { model.editor.format(.taskList) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        // Replacing drops Show/Hide Toolbar, which would collapse the title bar the top row is drawn in.
        CommandGroup(replacing: .toolbar) {
            Button("Command Palette") { model.toggle(.palette) }
                .keyboardShortcut("k")
            Toggle("Formatting Bar", isOn: Binding(get: { !model.formatBarHidden }, set: { model.formatBarHidden = !$0 }))
            Button(model.sidePane ? "Hide Side Pane" : "Show Side Pane") { model.toggleSidePane() }
                .keyboardShortcut("s", modifiers: [.command, .control])
        }
        CommandGroup(before: .windowArrangement) {
            Toggle("Always on Top", isOn: $model.floating)
            Divider()
        }
    }
}
