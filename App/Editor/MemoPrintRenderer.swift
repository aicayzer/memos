import AppKit
import WebKit

@MainActor
final class MemoPrintRenderer: NSObject, WKNavigationDelegate {
    private let view: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792), configuration: configuration)
    }()
    // WebKit needs a window-backed drawing surface for complete native print output.
    private let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 612, height: 792), styleMask: [.borderless], backing: .buffered, defer: false)
    private var printContinuation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, any Error>?

    func load(_ html: String) async throws {
        window.isReleasedWhenClosed = false
        window.contentView = view
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

    func printOperation(with info: NSPrintInfo) -> NSPrintOperation {
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false
        return view.printOperation(with: info)
    }

    func printDocument(in window: NSWindow) async -> Bool {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let operation = printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return await run(operation, in: window)
    }

    func run(_ operation: NSPrintOperation, in presentingWindow: NSWindow? = nil) async -> Bool {
        guard printContinuation == nil else { return false }
        // WebKit computes print pages asynchronously; synchronous main-thread printing cannot await them.
        operation.canSpawnSeparateThread = true
        return await withCheckedContinuation { continuation in
            printContinuation = continuation
            operation.runModal(for: presentingWindow ?? window, delegate: self,
                               didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc nonisolated private func printDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in
            let continuation = self.printContinuation
            self.printContinuation = nil
            continuation?.resume(returning: success)
        }
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
