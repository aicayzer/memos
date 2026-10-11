import AppKit
import WebKit

@MainActor
final class MemoPrintRenderer: NSObject, WKNavigationDelegate {
    private let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, any Error>?

    func load(_ html: String) async throws {
        view.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            view.loadHTMLString(html, baseURL: nil)
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                self.view.stopLoading()
                self.complete(MemoEditorError.unavailable)
            }
        }
        _ = try await view.callAsyncJavaScript("""
        await Promise.race([
          (async () => { await document.fonts.ready; await Promise.all(Array.from(document.images, image => image.decode())); })(),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Print content could not finish loading.')), 15000))
        ]);
        """, arguments: [:], in: nil, contentWorld: .page)
    }

    func printDocument() {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false
        let operation = view.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // The synchronous panel keeps the frozen document alive through printing and PDF export.
        operation.run()
    }

    private func complete(_ error: (any Error)?) {
        timeout?.cancel()
        timeout = nil
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
        continuation = nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { complete(MemoEditorError.unavailable) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        complete(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        complete(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        complete(error)
    }
}
