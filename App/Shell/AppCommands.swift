import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Memo") { Task { await model.newMemo() } }
                .keyboardShortcut("n")
            Button("Duplicate Memo") { Task { await model.duplicate() } }
                .keyboardShortcut("d")
            Button(model.current?.pinned == true ? "Unpin Memo" : "Pin Memo") { Task { await model.togglePin() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
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
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find in Memo") { model.toggle(.find) }
                .keyboardShortcut("f")
        }
        CommandGroup(after: .toolbar) {
            Button("Command Palette") { model.toggle(.palette) }
                .keyboardShortcut("k")
            Toggle("Formatting Bar", isOn: Binding(get: { !model.formatBarHidden }, set: { model.formatBarHidden = !$0 }))
        }
        CommandGroup(before: .windowArrangement) {
            Toggle("Always on Top", isOn: Binding(get: { model.floating }, set: { model.floating = $0 }))
            Divider()
        }
    }
}
