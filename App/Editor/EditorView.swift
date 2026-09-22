import SwiftUI

struct EditorView: NSViewRepresentable {
    let editor: any Editing

    func makeNSView(context: Context) -> NSView {
        editor.contentView
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
