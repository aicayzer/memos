import AppKit
import Observation
import OSLog
import WebKit

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "editor")

@MainActor
@Observable
final class EditorController: NSObject {
    private(set) var caret = CaretState()
    private(set) var isReady = false

    var onChanged: (String) -> Void = { _ in }
    var onOpenLink: (URL) -> Void = { _ in }
    var onCopy: (String) -> Void = { _ in }
    var accentOverride: NSColor? {
        didSet { applyAccent() }
    }

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var pendingMarkdown: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var editorURL: URL?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        #if DEBUG
        webView.isInspectable = true
        #endif
        // The content controller retains its handlers, so a proxy keeps the cycle out.
        configuration.userContentController.add(MessageProxy(target: self), name: "host")
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            window.addEventListener('error', (event) => {
              webkit.messageHandlers.host.postMessage({ type: 'error', message: String(event.message) })
            })
            window.addEventListener('unhandledrejection', (event) => {
              webkit.messageHandlers.host.postMessage({ type: 'error', message: String(event.reason) })
            })
            """,
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        // Lets the window's own background show through the page.
        webView.setValue(false, forKey: "drawsBackground")

        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyAccent() }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemColorsDidChange), name: NSColor.systemColorsDidChangeNotification, object: nil
        )

        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor") else {
            preconditionFailure("Editor/index.html missing from the bundle")
        }
        editorURL = url
        log.info("loading editor")
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func load(_ markdown: String) {
        guard isReady else {
            pendingMarkdown = markdown
            return
        }
        // Edits report the generation they belong to, so a late report for the previous document is dropped.
        generation += 1
        call("load", json(markdown), String(generation))
        focus()
    }

    func format(_ command: FormatCommand, argument: String? = nil) {
        if let argument {
            call("format", json(command.rawValue), json(argument))
        } else {
            call("format", json(command.rawValue))
        }
    }

    func focus() {
        webView.window?.makeFirstResponder(webView)
        call("focus")
    }

    /// The document as markdown, or nil while it is still what was loaded.
    func markdown() async -> String? {
        guard isReady else { return nil }
        let result = try? await webView.evaluateJavaScript("window.editor.markdown()")
        return result as? String
    }

    private func call(_ function: String, _ arguments: String...) {
        webView.evaluateJavaScript("window.editor.\(function)(\(arguments.joined(separator: ", ")))") { _, error in
            if let error {
                let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                log.error("\(function, privacy: .public): \(detail, privacy: .public)")
            }
        }
    }

    private func json(_ string: String) -> String {
        let data = try! JSONEncoder().encode(string)
        return String(decoding: data, as: UTF8.self)
    }

    @objc private func systemColorsDidChange() {
        applyAccent()
    }

    private func applyAccent() {
        guard isReady else { return }
        var hex: String?
        // The standard and system accents are dynamic colors; they resolve in whatever appearance is current.
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            hex = (accentOverride ?? NSColor.controlAccentColor).hexString
        }
        guard let hex else { return }
        call("setAccent", json(hex))
    }

    fileprivate func receive(_ message: EditorMessage) {
        switch message {
        case .ready:
            log.info("editor ready")
            isReady = true
            applyAccent()
            if let pendingMarkdown {
                self.pendingMarkdown = nil
                load(pendingMarkdown)
            }
        case .changed(let markdown, let generation):
            if generation == self.generation { onChanged(markdown) }
        case .state(let state):
            if state != caret { caret = state }
        case .openLink(let href):
            if let url = URL(string: href), let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme) {
                onOpenLink(url)
            }
        case .copy(let text):
            onCopy(text)
        case .error(let message):
            log.error("editor script error: \(message, privacy: .public)")
        }
    }
}

private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: EditorController?

    init(target: EditorController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let parsed = EditorMessage(body: message.body) else {
            log.error("unreadable editor message: \(String(describing: message.body), privacy: .public)")
            return
        }
        target?.receive(parsed)
    }
}

extension EditorController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(action.request.url == editorURL ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.info("editor page loaded")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        log.error("editor navigation failed: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        log.error("editor load failed: \(error.localizedDescription, privacy: .public)")
    }
}
