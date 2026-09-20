import SwiftUI

struct MainView: View {
    @State private var editor = EditorController()
    @State private var title = Memo.untitled

    var body: some View {
        EditorView(controller: editor)
            .navigationTitle(title)
            .onAppear {
                editor.onChanged = { markdown in title = Memo.title(for: markdown) }
                editor.onOpenLink = { NSWorkspace.shared.open($0) }
                editor.load("")
            }
    }
}
