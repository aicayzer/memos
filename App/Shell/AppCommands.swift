import AppKit
import SwiftUI

struct AppCommands: Commands {
    @Bindable var model: AppModel

    private var editorOwnsHistory: Bool {
        model.editor.contentView.ownsFirstResponder(in: NSApp.keyWindow)
    }

    private var canUndo: Bool { editorOwnsHistory ? model.editor.caret.commands["undo"] == true : NSApp.keyWindow?.firstResponder?.undoManager?.canUndo == true }
    private var canRedo: Bool { editorOwnsHistory ? model.editor.caret.commands["redo"] == true : NSApp.keyWindow?.firstResponder?.undoManager?.canRedo == true }

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
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { if editorOwnsHistory { model.editor.undo() } else { NSApp.keyWindow?.firstResponder?.undoManager?.undo() } }.keyboardShortcut("z").disabled(!canUndo)
            Button("Redo") { if editorOwnsHistory { model.editor.redo() } else { NSApp.keyWindow?.firstResponder?.undoManager?.redo() } }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!canRedo)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { model.printMemo() }.disabled(model.current == nil)
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
                tableItem("Insert Table", "insert")
                tableItem("Add Row Before", "addRowBefore")
                tableItem("Add Row After", "addRowAfter")
                tableItem("Add Column Before", "addColumnBefore")
                tableItem("Add Column After", "addColumnAfter")
                tableItem("Delete Row", "deleteRow")
                tableItem("Delete Column", "deleteColumn")
                tableItem("Delete Table", "deleteTable")
                tableItem("Align Left", "alignLeft")
                tableItem("Align Center", "alignCenter")
                tableItem("Align Right", "alignRight")
                Divider()
                tableItem("Move Row Up", "moveRowUp")
                tableItem("Move Row Down", "moveRowDown")
                tableItem("Move Column Left", "moveColumnLeft")
                tableItem("Move Column Right", "moveColumnRight")
                Menu("Sort Rows") {
                    sortItem("Text Ascending", "ascending", numeric: false)
                    sortItem("Text Descending", "descending", numeric: false)
                    sortItem("Numbers Ascending", "ascending", numeric: true)
                    sortItem("Numbers Descending", "descending", numeric: true)
                }.disabled(model.editor.caret.tables["sortRows"] != true)
                tableItem("Exit Table", "exit")
            }
        }
        // Replacing drops Show/Hide Toolbar, which would collapse the title bar the top row is drawn in.
        CommandGroup(replacing: .toolbar) {
            Toggle("Markdown Source", isOn: Binding(get: { model.editor.caret.sourceMode }, set: { model.editor.setSourceMode($0) }))
                .disabled(model.current == nil)
            item(.palette)
            Toggle("Formatting Bar", isOn: Binding(get: { !model.formatBarHidden }, set: { model.formatBarHidden = !$0 }))
            item(.sidePane, title: model.sidePane ? "Hide Side Pane" : "Show Side Pane")
        }
        CommandGroup(before: .windowArrangement) {
            Toggle("Always on Top", isOn: $model.floating)
            Divider()
        }
    }

    private func sortItem(_ title: String, _ order: String, numeric: Bool) -> some View {
        Button(title) { model.editor.sortTable(order: order, numeric: numeric) }
    }

    private func tableItem(_ title: String, _ command: String) -> some View {
        Button(title) { model.table(command) }.disabled(model.editor.caret.tables[command] != true)
    }

    private func formatName(_ shortcut: Shortcut) -> String? {
        switch shortcut {
        case .heading1, .heading2, .heading3: "heading"
        case .paragraph: "paragraph"
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .code: "code"
        case .codeBlock: "codeBlock"
        case .quote: "quote"
        case .bulletList: "bulletList"
        case .orderedList: "orderedList"
        case .taskList: "taskList"
        default: nil
        }
    }

    /// A menu item carries the shortcut's first key; the window matches the others.
    private func item(_ shortcut: Shortcut, title: String? = nil) -> some View {
        Button(title ?? shortcut.title) { model.perform(shortcut) }
            .keyboardShortcut(model.shortcuts.keyboardShortcut(shortcut))
            .disabled(formatName(shortcut).map { model.editor.caret.formats[$0] != true } ?? false)
    }
}
