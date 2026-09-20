import SwiftUI
import WebKit

struct EditorView: NSViewRepresentable {
    let controller: EditorController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}
