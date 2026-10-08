import SwiftUI

struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            item(.newMemo)
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
            Button("Save") { Task { _ = await model.flush() } }
                .keyboardShortcut("s", modifiers: .command)
        }
        CommandGroup(after: .saveItem) {
            Divider()
            item(.saveAs)
            Button("Share…") { Task { await model.share() } }
        }
        CommandGroup(after: .pasteboard) {
            Button("Paste as Plain Text") { model.pasteAsPlainText() }
                .keyboardShortcut("v", modifiers: [.command, .option, .shift])
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
            Divider()
            Menu("Table") {
                Button("Insert Table") { model.table("insert") }
                Button("Add Row Before") { model.table("addRowBefore") }
                Button("Add Row After") { model.table("addRowAfter") }
                Button("Add Column Before") { model.table("addColumnBefore") }
                Button("Add Column After") { model.table("addColumnAfter") }
                Button("Delete Row") { model.table("deleteRow") }
                Button("Delete Column") { model.table("deleteColumn") }
                Button("Delete Table") { model.table("deleteTable") }
                Button("Align Left") { model.table("alignLeft") }
                Button("Align Center") { model.table("alignCenter") }
                Button("Align Right") { model.table("alignRight") }
                Button("Exit Table") { model.table("exit") }
            }
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
    }
}
