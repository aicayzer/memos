import AppKit
import Observation
import OSLog
import WebKit

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "editor")
private let retryableSnapshotCodes: Set<String> = ["not-ready", "stale-document", "composition", "operation-pending", "preservation"]

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
    var allowsFocus = true
    var documentID = ""

    var onChanged: (String) -> Void = { _ in }
    var onOpenLink: (URL) -> Void = { _ in }
    var onCopy: (String) -> Void = { _ in }
    var onWarning: (String) -> Void = { _ in }
    var onDropFiles: ([URL], CGPoint) -> Void = { _, _ in }
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
    @ObservationIgnored private var refreshPreviousGeneration: Int?
    @ObservationIgnored private var refreshChanges: [(text: String, generation: Int, sequence: Int)] = []
    @ObservationIgnored private var lastChangeSequence = 0
    @ObservationIgnored private var loadTask: Task<Void, any Error>?
    @ObservationIgnored private var failure: (any Error)?
    @ObservationIgnored private var pageReady = false
    @ObservationIgnored private var editorURL: URL?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var imageHandler: ImageSchemeHandler?

    @ObservationIgnored private let images: any ImageStore

    init(images: any ImageStore) {
        self.images = images
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        let handler = ImageSchemeHandler(images: images)
        configuration.setURLSchemeHandler(handler, forURLScheme: ImageSchemeHandler.scheme)
        imageHandler = handler
        webView = EditorWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.onPaste = { [weak self] in self?.pasteCapturedClipboard() ?? false }
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

    func load(_ markdown: String) { replace(markdown, keepingCaret: false) }

    func reload(_ markdown: String) { replace(markdown, keepingCaret: true) }

    private func replace(_ markdown: String, keepingCaret: Bool) {
        refreshPreviousGeneration = nil
        refreshChanges.removeAll()
        generation += 1
        pendingMarkdown = markdown
        isReady = false
        guard pageReady else { return }
        applyDocument(markdown, keepingCaret: keepingCaret)
    }

    private func applyDocument(_ markdown: String, keepingCaret: Bool) {
        pendingMarkdown = nil
        let expectedGeneration = generation
        let expectedDocumentID = documentID
        let method = keepingCaret ? "reload" : "load"
        loadTask = Task { @MainActor [weak self] in
            guard let self else { throw MemoEditorError.unavailable }
            do {
                guard self.generation == expectedGeneration, self.documentID == expectedDocumentID else { throw MemoEditorError.documentChanged }
                _ = try await self.webView.evaluateJavaScript("window.editor.\(method)(\(json(markdown)), \(expectedGeneration), \(json(expectedDocumentID)))")
                guard self.generation == expectedGeneration, self.documentID == expectedDocumentID else { throw MemoEditorError.documentChanged }
                self.failure = nil
                self.isReady = true
                if !keepingCaret { self.focus() }
            } catch {
                if self.generation == expectedGeneration, self.documentID == expectedDocumentID { self.failure = error }
                throw error
            }
        }
    }

    func format(_ command: FormatCommand, argument: String?) {
        if let argument {
            call("format", json(command.rawValue), json(argument))
        } else {
            call("format", json(command.rawValue))
        }
    }

    func focus() {
        guard allowsFocus, webView.window?.isKeyWindow == true else { return }
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

    func table(_ command: String) {
        guard isReady else { return }
        call("table", json(command))
    }

    func pasteAsPlainText(_ text: String) {
        guard isReady else { return }
        call("pasteAsPlainText", json(text))
    }

    func snapshot() async throws -> String {
        let expectedGeneration = generation
        let deadline = ContinuousClock.now + .seconds(15)
        while !pageReady, failure == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            guard expectedGeneration == generation else { throw MemoEditorError.documentChanged }
        }
        if let loadTask { try await loadTask.value }
        guard expectedGeneration == generation else { throw MemoEditorError.documentChanged }
        if let failure { throw failure }
        guard isReady else { throw MemoEditorError.notReady }
        let result = try await webView.evaluateJavaScript("window.editor.snapshot(\(expectedGeneration))")
        guard expectedGeneration == generation else { throw MemoEditorError.documentChanged }
        if let rejected = result as? [String: Any],
           let code = rejected["snapshotError"] as? String, let message = rejected["message"] as? String {
            if retryableSnapshotCodes.contains(code) {
                throw MemoEditorError.snapshotRejected(code: code, message: message)
            }
            let error = MemoEditorError.script(message)
            failure = error
            isReady = false
            throw error
        }
        guard let value = result as? [String: Any],
              let text = value["text"] as? String,
              value["format"] as? String == "md",
              value["revision"] is Int, value["dirty"] is Bool,
              value["documentId"] as? String == documentID,
              value["generation"] as? Int == expectedGeneration else { throw MemoEditorError.invalidResponse }
        return text
    }

    func rebind(to nextDocumentID: String) async throws -> String {
        let previousGeneration = generation
        let previousDocumentID = documentID
        if let loadTask { try await loadTask.value }
        guard previousGeneration == generation, previousDocumentID == documentID else { throw MemoEditorError.documentChanged }
        if let failure { throw failure }
        guard isReady else { throw MemoEditorError.notReady }
        let nextGeneration = previousGeneration + 1
        generation = nextGeneration
        documentID = nextDocumentID
        isReady = false
        do {
            let result = try await webView.evaluateJavaScript("window.editor.rebind(\(previousGeneration), \(nextGeneration), \(json(previousDocumentID)), \(json(nextDocumentID)))")
            guard generation == nextGeneration, documentID == nextDocumentID else { throw MemoEditorError.documentChanged }
            if let rejected = result as? [String: Any], rejected["rejected"] as? Bool == true,
               let code = rejected["snapshotError"] as? String, retryableSnapshotCodes.contains(code),
               rejected["generation"] as? Int == previousGeneration,
               rejected["documentId"] as? String == previousDocumentID,
               let message = rejected["message"] as? String {
                generation = previousGeneration
                documentID = previousDocumentID
                isReady = true
                throw MemoEditorError.script(message)
            }
            guard let value = result as? [String: Any],
                  let text = value["text"] as? String,
                  value["documentId"] as? String == nextDocumentID,
                  value["generation"] as? Int == nextGeneration else { throw MemoEditorError.invalidResponse }
            isReady = true
            loadTask = nil
            return text
        } catch {
            // Unknown script failures may have committed a new page scope; do not claim the old one.
            if generation == nextGeneration, documentID == nextDocumentID {
                failure = error
            }
            throw error
        }
    }

    func refresh(_ markdown: String, documentID nextDocumentID: String, expecting source: String) async throws -> EditorRefresh {
        let previousGeneration = generation
        let previousDocumentID = documentID
        if let loadTask { try await loadTask.value }
        guard previousGeneration == generation, previousDocumentID == documentID else { throw MemoEditorError.documentChanged }
        if let failure { throw failure }
        guard isReady else { throw MemoEditorError.notReady }
        let nextGeneration = previousGeneration + 1
        generation = nextGeneration
        documentID = nextDocumentID
        refreshPreviousGeneration = previousGeneration
        refreshChanges.removeAll()
        isReady = false
        defer {
            if generation == nextGeneration || generation == previousGeneration {
                refreshPreviousGeneration = nil
                refreshChanges.removeAll()
            }
        }
        do {
            let result = try await webView.evaluateJavaScript("window.editor.refresh(\(previousGeneration), \(nextGeneration), \(json(previousDocumentID)), \(json(nextDocumentID)), \(json(source)), \(json(markdown)))")
            guard generation == nextGeneration, documentID == nextDocumentID else { throw MemoEditorError.documentChanged }
            if let value = result as? [String: Any],
               value["generation"] as? Int == previousGeneration,
               value["documentId"] as? String == previousDocumentID {
                if value["rejected"] as? Bool == true,
                   let code = value["snapshotError"] as? String, retryableSnapshotCodes.contains(code),
                   let message = value["message"] as? String {
                    generation = previousGeneration
                    documentID = previousDocumentID
                    isReady = true
                    if let newer = refreshChanges.filter({ $0.generation == previousGeneration && $0.sequence > lastChangeSequence }).max(by: { $0.sequence < $1.sequence }) {
                        lastChangeSequence = newer.sequence
                        onChanged(newer.text)
                    }
                    throw MemoEditorError.snapshotRejected(code: code, message: message)
                }
                if value["applied"] as? Bool == false, let live = value["text"] as? String,
                   let sequence = value["sequence"] as? Int {
                    generation = previousGeneration
                    documentID = previousDocumentID
                    isReady = true
                    lastChangeSequence = max(lastChangeSequence, sequence)
                    let newer = refreshChanges.filter { $0.generation == previousGeneration && $0.sequence > sequence }.max { $0.sequence < $1.sequence }
                    if let newer { lastChangeSequence = max(lastChangeSequence, newer.sequence) }
                    return .edited(newer?.text ?? live)
                }
            }
            guard let value = result as? [String: Any], value["applied"] as? Bool == true,
                  value["text"] as? String == markdown,
                  value["documentId"] as? String == nextDocumentID,
                  value["generation"] as? Int == nextGeneration,
                  let sequence = value["sequence"] as? Int else { throw MemoEditorError.invalidResponse }
            lastChangeSequence = max(lastChangeSequence, sequence)
            isReady = true
            loadTask = nil
            if let newer = refreshChanges.filter({ $0.generation == nextGeneration && $0.sequence > sequence }).max(by: { $0.sequence < $1.sequence }) {
                lastChangeSequence = max(lastChangeSequence, newer.sequence)
                onChanged(newer.text)
            }
            return .applied
        } catch {
            if generation == nextGeneration, documentID == nextDocumentID { failure = error }
            throw error
        }
    }

    func pasteCapturedClipboard(from pasteboard: NSPasteboard = .general) -> Bool {
        guard isReady else { return false }
        let expectedGeneration = generation
        let expectedDocumentID = documentID
        var capturedImages: [[String: String]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                guard let data = item.data(forType: type) else { continue }
                capturedImages.append(["bytesBase64": data.base64EncodedString(), "mimeType": type == .png ? "image/png" : "image/tiff"])
                break
            }
        }
        var text = pasteboard.string(forType: .string) ?? ""
        var html = pasteboard.string(forType: .html)
        let richData = pasteboard.data(forType: .rtfd) ?? pasteboard.data(forType: .rtf)
        let richType: NSAttributedString.DocumentType = pasteboard.data(forType: .rtfd) == nil ? .rtf : .rtfd
        if let richData, let rich = try? NSAttributedString(data: richData, options: [.documentType: richType], documentAttributes: nil) {
            if text.isEmpty { text = rich.string.replacingOccurrences(of: "\u{FFFC}", with: "") }
            var attachments: [[String: String]] = []
            rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
                guard let attachment = value as? NSTextAttachment,
                      let original = attachment.fileWrapper?.regularFileContents ?? attachment.contents,
                      let image = MemoClipboard.supportedImage(original) else { return }
                let bytes = image.bytes
                let type = image.type
                let encoded = bytes.base64EncodedString()
                attachments.append(["bytesBase64": encoded, "mimeType": type.mimeType, "source": "data:\(type.mimeType);base64,\(encoded)"])
            }
            if !attachments.isEmpty {
                capturedImages = attachments
                if let supplied = html, let matched = try? MemoClipboard.replacingImageSources(in: supplied, attachments: attachments) {
                    html = matched
                }
            }
            if html == nil, let generated = try? MemoClipboard.formattedHTML(from: rich) {
                html = try? MemoClipboard.replacingImageSources(in: generated, attachments: attachments)
            }
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls {
            guard let data = try? Data(contentsOf: url), let type = ImageType(sniffing: data) else { continue }
            capturedImages.append(["bytesBase64": data.base64EncodedString(), "mimeType": type.mimeType, "filename": url.lastPathComponent])
        }
        if html != nil {
            for index in capturedImages.indices where capturedImages[index]["source"] == nil {
                capturedImages[index]["source"] = "native-unassociated:\(index)"
            }
        }
        guard !text.isEmpty || html != nil || !capturedImages.isEmpty else { return false }
        struct CapturedPaste: Encodable {
            let text: String
            let html: String?
            let generation: Int
            let images: [[String: String]]
        }
        guard expectedGeneration == generation, expectedDocumentID == documentID else {
            onWarning(MemoEditorError.documentChanged.localizedDescription)
            return true
        }
        call("pasteNative", json(CapturedPaste(text: text, html: html, generation: expectedGeneration, images: capturedImages)))
        return true
    }

    func imageRequest(_ body: [String: Any]) async {
        guard let requestID = body["requestId"] as? String,
              let expectedGeneration = body["generation"] as? Int,
              let capturedDocumentID = body["documentId"] as? String else { return }
        var response: [String: String] = [:]
        do {
            if let failure { throw failure }
            guard generation == expectedGeneration, documentID == capturedDocumentID else { throw MemoEditorError.documentChanged }
            if body["action"] as? String == "import" {
                guard let encoded = body["bytesBase64"] as? String, let captured = Data(base64Encoded: encoded) else {
                    throw MemoEditorError.invalidResponse
                }
                guard let image = MemoClipboard.supportedImage(captured) else { throw ImageStoreError.unsupported }
                let reference = try await images.save(image.bytes).path
                response = ["reference": reference]
            } else if body["action"] as? String == "export" {
                guard let reference = body["reference"] as? String else { throw MemoEditorError.invalidResponse }
                guard let url = await images.url(for: reference) else { throw MemoEditorError.unavailable }
                let data = try Data(contentsOf: url)
                guard let type = ImageType(sniffing: data) else { throw MemoEditorError.invalidResponse }
                response = ["bytesBase64": data.base64EncodedString(), "mimeType": type.mimeType]
            } else { throw MemoEditorError.invalidResponse }
            if let failure { throw failure }
            guard generation == expectedGeneration, documentID == capturedDocumentID else { throw MemoEditorError.documentChanged }
        } catch { response = ["error": error.localizedDescription] }
        call("imageResponse", json(requestID), json(response))
    }

    func writeClipboard(_ body: [String: Any], to pasteboard: NSPasteboard = .general) {
        guard let requestID = body["requestId"] as? String else { return }
        var response: [String: String] = [:]
        do {
            if let failure { throw failure }
            guard let expectedGeneration = body["generation"] as? Int, expectedGeneration == generation,
                  body["documentId"] as? String == documentID,
                  let text = body["text"] as? String, let html = body["html"] as? String else { throw MemoEditorError.documentChanged }
            let item = try MemoClipboard.item(text: text, html: html, images: body["images"] as? [[String: String]] ?? [])
            if let failure { throw failure }
            guard expectedGeneration == generation, body["documentId"] as? String == documentID else { throw MemoEditorError.documentChanged }
            try MemoClipboard.write(item, to: pasteboard)
        } catch { response = ["error": error.localizedDescription] }
        call("clipboardResponse", json(requestID), json(response))
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
            pageReady = true
            lastChangeSequence = 0
            isReady = true
            applyAccent()
            applyTextSize()
            applyKeymap()
            if let pendingMarkdown {
                self.pendingMarkdown = nil
                applyDocument(pendingMarkdown, keepingCaret: false)
            }
        case .changed(let markdown, let generation, let sequence):
            guard failure == nil else { return }
            if let previous = refreshPreviousGeneration {
                if (generation == self.generation || generation == previous), let sequence {
                    refreshChanges.append((markdown, generation, sequence))
                }
                return
            }
            guard generation == self.generation else { return }
            if let sequence {
                guard sequence > lastChangeSequence else { return }
                lastChangeSequence = sequence
            }
            onChanged(markdown)
        case .state(let state):
            if state != caret { caret = state }
        case .openLink(let href):
            if let url = URL(string: href), let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme) {
                onOpenLink(url)
            }
        case .copy(let text):
            onCopy(text)
        case .warning(let message):
            onWarning(message)
        case .error(let message):
            failure = MemoEditorError.script(message)
            log.error("editor script error: \(message, privacy: .public)")
        }
    }
}

enum MemoEditorError: LocalizedError {
    case notReady, unavailable, documentChanged, invalidResponse
    case script(String)
    case snapshotRejected(code: String, message: String)
    var errorDescription: String? {
        switch self {
        case .notReady: "The editor is still loading. Try again in a moment."
        case .documentChanged: "Your memo changed. Try again."
        case .invalidResponse, .unavailable: "Couldn’t read your memo. Your text is still open."
        case .script: "The editor couldn’t complete that action. Your text is still open."
        case .snapshotRejected(let code, _):
            switch code {
            case "composition": "Finish entering text before trying again."
            case "operation-pending": "An image is still being added. Try again in a moment."
            case "not-ready": "The editor is still loading. Try again in a moment."
            case "stale-document": "Your memo changed. Try again."
            default: "Couldn’t preserve your memo’s Markdown. Your text is still open."
            }
        }
    }
}

private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: EditorController?

    init(target: EditorController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        if let body = message.body as? [String: Any] {
            if body["type"] as? String == "imageRequest" {
                Task { await target?.imageRequest(body) }
                return
            }
            if body["type"] as? String == "writeClipboard" {
                target?.writeClipboard(body)
                return
            }
        }
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        isReady = false
        failure = MemoEditorError.unavailable
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.info("editor page loaded")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        failure = error
        isReady = false
        log.error("editor navigation failed: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        log.error("editor load failed: \(error.localizedDescription, privacy: .public)")
    }
}
