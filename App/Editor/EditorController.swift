import AppKit
import Observation
import OSLog
import WebKit

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "editor")

/// The memo's text size, in points. The stylesheet's own default is Medium's.
enum TextSize: Double, CaseIterable, Identifiable {
    case small = 13, medium = 15, large = 17

    var id: Double { rawValue }
    var points: Double { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// The nearest size to a stored one, which may come from another version or an edited preference.
    init(nearest points: Double) {
        self = Self.allCases.min { abs($0.rawValue - points) < abs($1.rawValue - points) } ?? .medium
    }
}

@MainActor
@Observable
final class EditorController: NSObject, Editing {
    private(set) var caret = CaretState()
    private(set) var isReady = false

    var onChanged: (String) -> Void = { _ in }
    var onOpenLink: (URL) -> Void = { _ in }
    var onCopy: (String) -> Void = { _ in }
    var onDropFiles: ([URL], CGPoint) -> Void = { _, _ in }
    var onPasteImage: () -> Void = {}
    var accentOverride: NSColor? {
        didSet { applyAccent() }
    }
    var textSize = TextSize.medium.points {
        didSet { applyTextSize() }
    }
    /// The editor's key bindings, by shortcut name; the app owns them, since Settings edits them.
    var keymap: [String: [String]] = [:] {
        didSet { applyKeymap() }
    }

    @ObservationIgnored let webView: EditorWebView
    var contentView: NSView { webView }

    @ObservationIgnored private var pendingMarkdown: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var editorURL: URL?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var imageHandler: ImageSchemeHandler?

    init(images: any ImageStore) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        let handler = ImageSchemeHandler(images: images)
        configuration.setURLSchemeHandler(handler, forURLScheme: ImageSchemeHandler.scheme)
        imageHandler = handler
        webView = EditorWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.onDropFiles = { [weak self] urls, point in self?.onDropFiles(urls, point) }
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

    /// The same memo, changed under the window: the text is replaced where the caret and the scroll are.
    func reload(_ markdown: String) {
        guard isReady else {
            pendingMarkdown = markdown
            return
        }
        generation += 1
        call("reload", json(markdown), String(generation))
    }

    func format(_ command: FormatCommand, argument: String?) {
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

    func find(_ text: String) { call("find", json(text)) }

    /// Inserts the paths as lines at a point in the view, and takes the keyboard, as typing there would.
    func insertPaths(_ paths: [String], at point: CGPoint) {
        webView.window?.makeFirstResponder(webView)
        call("insertPaths", json(paths), String(Double(point.x)), String(Double(point.y)))
    }

    /// Inserts the images at a point in the view, or where the caret is when a paste brought them.
    func insertImages(_ references: [ImageReference], at point: CGPoint?) {
        webView.window?.makeFirstResponder(webView)
        let payload = references.map { ["path": $0.path, "alt": $0.alt] }
        call("insertImages", json(payload), point.map { String(Double($0.x)) } ?? "null", point.map { String(Double($0.y)) } ?? "null")
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

    private func json(_ value: some Encodable) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func applyKeymap() {
        guard isReady else { return }
        call("setKeymap", json(keymap))
    }

    private func applyTextSize() {
        guard isReady else { return }
        call("setTextSize", json(textSize))
    }

    @objc private func systemColorsDidChange() {
        applyAccent()
    }

    private func applyAccent() {
        guard isReady else { return }
        var hex: String?
        // The standard and system accents are dynamic; a hex needs an appearance to resolve in.
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            hex = (accentOverride ?? NSColor.controlAccentColor).hexString
        }
        guard let hex else { return }
        call("setAccent", json(hex))
    }

    func receive(_ message: EditorMessage) {
        switch message {
        case .ready:
            log.info("editor ready")
            isReady = true
            applyAccent()
            applyTextSize()
            applyKeymap()
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
        case .pasteImage:
            onPasteImage()
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
            // The body may hold the memo, which does not belong in the log; its type says what went wrong.
            log.error("unreadable editor message of type \(String(describing: (message.body as? [String: Any])?["type"]), privacy: .public)")
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
