import SwiftUI
import WebKit

struct EditorView: NSViewRepresentable {
    let controller: EditorController

    func makeNSView(context: Context) -> EditorWebView {
        controller.webView
    }

    func updateNSView(_ view: EditorWebView, context: Context) {}
}
