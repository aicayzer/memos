import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        EditorView(controller: model.editor)
            .navigationTitle(model.title)
            .task { await model.start() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard (note.object as? NSWindow) === model.editor.webView.window else { return }
                Task { await model.flush() }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await model.newMemo() }
                    } label: {
                        Label("New Memo", systemImage: "plus")
                    }
                }
            }
    }
}
