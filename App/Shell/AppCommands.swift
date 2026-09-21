import SwiftUI

struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Memo") { Task { await model.newMemo() } }
                .keyboardShortcut(Shortcut.newMemo.keyboardShortcut)
            Button("Duplicate Memo") { Task { await model.duplicate() } }
                .keyboardShortcut(Shortcut.duplicate.keyboardShortcut)
            Button(model.current?.favorite == true ? "Unfavorite Memo" : "Favorite Memo") { Task { await model.toggleFavorite() } }
                .keyboardShortcut(Shortcut.favorite.keyboardShortcut)
            Divider()
            Button("Browse Memos") { model.toggle(.browse) }
                .keyboardShortcut(Shortcut.browse.keyboardShortcut)
            Button("Go Back") { Task { await model.goBack() } }
                .keyboardShortcut(Shortcut.back.keyboardShortcut)
                .disabled(!model.history.canGoBack)
            Button("Go Forward") { Task { await model.goForward() } }
                .keyboardShortcut(Shortcut.forward.keyboardShortcut)
                .disabled(!model.history.canGoForward)
            Divider()
            Button("Copy as Markdown") { model.copyAsMarkdown() }
                .keyboardShortcut(Shortcut.copyMarkdown.keyboardShortcut)
        }
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Save As…") { Task { await model.saveAs() } }
                .keyboardShortcut(Shortcut.saveAs.keyboardShortcut)
            Button("Share…") { Task { await model.share() } }
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find in Memo") { model.toggle(.find) }
                .keyboardShortcut(Shortcut.find.keyboardShortcut)
        }
        // The editor's own keys (⌘B, ⌘I) reach the web view first; these are the ones it does not have.
        CommandMenu("Format") {
            Button("Bulleted List") { model.editor.format(.bulletList) }
                .keyboardShortcut(Shortcut.bulletList.keyboardShortcut)
            Button("Task List") { model.editor.format(.taskList) }
                .keyboardShortcut(Shortcut.taskList.keyboardShortcut)
        }
        // Replacing drops Show/Hide Toolbar, which would collapse the title bar the top row is drawn in.
        CommandGroup(replacing: .toolbar) {
            Button("Command Palette") { model.toggle(.palette) }
                .keyboardShortcut(Shortcut.palette.keyboardShortcut)
            Toggle("Formatting Bar", isOn: Binding(get: { !model.formatBarHidden }, set: { model.formatBarHidden = !$0 }))
            Button(model.sidePane ? "Hide Side Pane" : "Show Side Pane") { model.toggleSidePane() }
                .keyboardShortcut(Shortcut.sidePane.keyboardShortcut)
        }
        CommandGroup(before: .windowArrangement) {
            Toggle("Always on Top", isOn: $model.floating)
            Divider()
        }
    }
}
