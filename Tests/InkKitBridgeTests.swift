import AppKit
import Testing
@testable import Memos

@MainActor
@Suite(.serialized, .opensWindows)
struct InkKitBridgeTests {
    @Test func recoveryRebindKeepsFreshSourceAndRejectsThePreviousScope() async throws {
        let editor = EditorController(images: FakeImageStore())
        editor.documentID = "original"
        editor.load("Original\n")
        _ = try await editor.snapshot()
        _ = try await editor.webView.evaluateJavaScript("window.editor.pasteAsPlainText(' fresh')")
        let live = try await editor.rebind(to: "recovered")
        #expect(live.contains("Original fresh"))
        #expect(editor.documentID == "recovered")
        #expect(editor.isReady)
        #expect(try await editor.snapshot() == live)
        var reported: [String] = []
        editor.onChanged = { reported.append($0) }
        editor.receive(.changed("stale", generation: 1))
        #expect(reported.isEmpty)
        editor.receive(.changed("current", generation: 2))
        #expect(reported == ["current"])
    }

    @Test func rejectedRecoverySnapshotRetainsTheOriginalScope() async throws {
        let editor = EditorController(images: FakeImageStore())
        editor.documentID = "original"
        editor.load("Original\n")
        _ = try await editor.snapshot()
        _ = try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').dispatchEvent(new CompositionEvent('compositionstart', {bubbles: true}))")
        await #expect(throws: (any Error).self) { try await editor.rebind(to: "recovered") }
        #expect(editor.documentID == "original")
        #expect(editor.isReady)
        _ = try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').dispatchEvent(new CompositionEvent('compositionend', {bubbles: true}))")
        #expect(try await editor.snapshot() == "Original\n")
    }

    @Test func pendingImageRecoveryRejectionLetsTheOriginalImportComplete() async throws {
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = SuspendedImageStore(backing: FolderImageStore(besideStoreAt: folder.appending(path: "store.json")))
        let bytes = makePNG().base64EncodedString()
        let editor = EditorController(images: images)
        editor.documentID = "original"
        editor.load("Original\n")
        _ = try await editor.snapshot()
        _ = try await editor.webView.evaluateJavaScript("""
        window.snapshotDiagnostics = {expected: [], global: []};
        window.originalSnapshot = window.editor.snapshot;
        window.editor.snapshot = (...args) => {
          try { return window.originalSnapshot(...args) }
          catch (error) { window.snapshotDiagnostics.expected.push({code: error.code || '', message: String(error), stack: error.stack || ''}); throw error }
        };
        window.addEventListener('error', event => { window.snapshotDiagnostics.global.push({message: event.message || '', filename: event.filename || '', stack: event.error?.stack || ''}) });
        true
        """)
        _ = try await editor.webView.evaluateJavaScript("window.editor.pasteNative({text:'',generation:1,images:[{bytesBase64:'\(bytes)',mimeType:'image/png'}]})")
        for _ in 0..<200 {
            if await images.isSaving { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(await images.isSaving)
        await #expect(throws: MemoEditorError.self) { try await editor.rebind(to: "recovered") }
        #expect(editor.documentID == "original")
        #expect(editor.isReady)
        await #expect(throws: (any Error).self) { try await editor.snapshot() }
        await images.complete()
        var live = ""
        var lastError = ""
        for _ in 0..<200 {
            do { live = try await editor.snapshot() } catch { lastError = String(reflecting: error) }
            if live.contains("images/") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let diagnostics = try await editor.webView.evaluateJavaScript("JSON.stringify(window.snapshotDiagnostics)") as? String ?? "No snapshot diagnostics"
        #expect(live.contains("Original"), "Snapshot diagnostics: \(diagnostics), last error: \(lastError)")
        #expect(live.contains("images/"), "Snapshot diagnostics: \(diagnostics), last error: \(lastError)")
        #expect(try await editor.rebind(to: "recovered") == live)
        #expect(editor.documentID == "recovered")
    }

    @Test func unknownRecoveryResponseFailsExplicitlyInsteadOfRestoringAnOldScope() async throws {
        let images = FakeImageStore()
        let editor = EditorController(images: images)
        let store = ChangeableStore([])
        let memo = await store.create(markdown: "Original\n")
        let suite = "failed-recovery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(store: store, images: FakeImageStore(), defaults: defaults, editor: editor, presentError: { _ in })
        await model.start()
        _ = try await editor.snapshot()
        _ = try await editor.webView.evaluateJavaScript("const rebind = window.editor.rebind; window.editor.rebind = (...args) => { rebind(...args); return {} }; true")
        await #expect(throws: MemoEditorError.self) { try await editor.rebind(to: "recovered") }
        #expect(!editor.isReady)
        await #expect(throws: MemoEditorError.self) { try await editor.snapshot() }
        editor.receive(.changed("Should not save against the original memo\n", generation: 2))
        #expect(model.current?.id == memo.id)
        #expect(model.current?.markdown == memo.markdown)
        #expect(!(await model.flush()))
        #expect(await store.get(memo.id)?.markdown == memo.markdown)
        _ = try await editor.webView.evaluateJavaScript("window.rpcResponses = {}; window.editor.imageResponse = (id, value) => { window.rpcResponses.image = value }; window.editor.clipboardResponse = (id, value) => { window.rpcResponses.clipboard = value }; true")
        await editor.imageRequest([
            "requestId": "blocked-image", "action": "import", "documentId": "recovered", "generation": 2,
            "bytesBase64": Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).base64EncodedString(),
        ])
        let pasteboard = NSPasteboard(name: .init("failed-recovery-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Previous clipboard", forType: .string)
        editor.writeClipboard([
            "requestId": "blocked-clipboard", "documentId": "recovered", "generation": 2,
            "text": "Replacement", "html": "<p>Replacement</p>",
        ], to: pasteboard)
        #expect(await images.held.isEmpty)
        #expect(pasteboard.string(forType: .string) == "Previous clipboard")
        let replies = try #require(try await editor.webView.evaluateJavaScript("window.rpcResponses") as? [String: [String: String]])
        #expect(replies["image"]?["error"] != nil)
        #expect(replies["clipboard"]?["error"] != nil)
    }

    @Test func aNewerLoadWinsOverRecoveryInFlight() async throws {
        let editor = EditorController(images: FakeImageStore())
        editor.documentID = "original"
        editor.load("Original\n")
        _ = try await editor.snapshot()
        let recovering = Task { try await editor.rebind(to: "recovered") }
        for _ in 0..<200 where editor.documentID == "original" { await Task.yield() }
        try #require(editor.documentID == "recovered")
        editor.documentID = "newer"
        editor.load("Newer\n")
        await #expect(throws: MemoEditorError.self) { try await recovering.value }
        #expect(try await editor.snapshot() == "Newer\n")
        #expect(editor.documentID == "newer")
        #expect(editor.isReady)
    }

    @Test func snapshotsIncludeUnchangedAndImmediatelyEditedSource() async throws {
        let editor = EditorController(images: FakeImageStore())
        editor.documentID = "fixture"
        editor.load("__original__\n\nTail\n")
        #expect(try await editor.snapshot() == "__original__\n\nTail\n")
        _ = try await editor.webView.evaluateJavaScript("window.editor.pasteAsPlainText(' now')")
        #expect(try await editor.snapshot().contains("Tail now"))
    }

    @Test func aRecoverableImageWarningDoesNotDisableSnapshots() async throws {
        let editor = EditorController(images: FakeImageStore())
        editor.documentID = "fixture"
        editor.load("Keep this memo\n")
        _ = try await editor.snapshot()
        var warnings = 0
        editor.onWarning = { _ in warnings += 1 }
        editor.receive(.warning("The image is unavailable."))
        #expect(warnings == 1)
        #expect(editor.isReady)
        #expect(try await editor.snapshot() == "Keep this memo\n")
    }

    @Test func aMissingStoredImageKeepsSnapshotsEditingAndPortableClipboardUsable() async throws {
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = FolderImageStore(besideStoreAt: folder.appending(path: "store.json"))
        let reference = try await images.save(makePNG())
        let file = try #require(await images.url(for: reference.path))
        try FileManager.default.removeItem(at: file)
        let editor = EditorController(images: images)
        editor.documentID = "fixture"
        editor.load("")
        _ = try await editor.snapshot()
        var warnings: [String] = []
        editor.onWarning = { warnings.append($0) }
        _ = try await editor.webView.evaluateJavaScript("window.assetEvents = []; document.addEventListener('error', event => { window.assetEvents.push({message: String(event.message || ''), target: event.target.tagName || '', filename: event.filename || ''}) }, true); true")
        let source = "Before\n\n![Missing picture](\(reference.path))\n\nAfter\n"
        editor.load(source)
        _ = try? await editor.snapshot()
        var observed = false
        for _ in 0..<200 {
            observed = (try await editor.webView.evaluateJavaScript("window.assetEvents.some(event => event.target === 'IMG')") as? Bool) == true
            if observed { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let diagnostics = try await editor.webView.evaluateJavaScript("JSON.stringify(window.assetEvents)") as? String ?? "No asset diagnostics"
        #expect(observed, "The missing reference must reach the native image loader: \(diagnostics)")
        #expect(try await editor.snapshot() == source, "Image diagnostics: \(diagnostics)")
        let clipboard = try #require(try await editor.webView.callAsyncJavaScript("return JSON.parse(JSON.stringify(await window.editor.clipboard()))", arguments: [:], in: nil, contentWorld: .page) as? [String: Any])
        let text = try #require(clipboard["text"] as? String)
        let html = try #require(clipboard["html"] as? String)
        #expect(text.contains("Before") && text.contains("Missing picture") && text.contains("After"))
        #expect(html.contains("Missing picture"))
        #expect(!html.contains("memo-image:"))
        for _ in 0..<200 {
            if !warnings.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!warnings.isEmpty)
        _ = try await editor.webView.evaluateJavaScript("window.editor.pasteAsPlainText(' more')")
        #expect(try await editor.snapshot().contains("After more"))
        #expect(editor.isReady)
    }

    @Test func rapidLoadsKeepOnlyTheCurrentDocument() async throws {
        let editor = EditorController(images: FakeImageStore())
        editor.documentID = "initial"
        editor.load("Initial\n")
        _ = try await editor.snapshot()
        for index in 0..<20 {
            editor.documentID = "memo-\(index)"
            editor.load("Memo \(index)\n")
        }
        #expect(try await editor.snapshot() == "Memo 19\n")
        #expect(editor.isReady)
    }

    @Test func scriptFailureCannotLookLikeAnUnchangedDocument() async throws {
        let editor = EditorController(images: FakeImageStore())
        editor.documentID = "fixture"
        editor.load("Keep this memo\n")
        _ = try await editor.snapshot()
        _ = try await editor.webView.evaluateJavaScript("delete window.editor")
        await #expect(throws: (any Error).self) { try await editor.snapshot() }
    }

    @Test func pendingImageImportCannotEnterANewMemo() async throws {
        let images = SuspendedImageStore()
        let editor = EditorController(images: images)
        editor.documentID = "first"
        editor.load("First\n")
        _ = try await editor.snapshot()
        _ = try await editor.webView.evaluateJavaScript("window.editor.pasteNative({text:'',generation:1,images:[{bytesBase64:'iVBORw0KGgo=',mimeType:'image/png'}]})")
        for _ in 0..<200 {
            if await images.isSaving { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await images.isSaving)
        editor.documentID = "second"
        editor.load("Second\n")
        await images.complete()
        for _ in 0..<200 {
            if (try? await editor.snapshot()) == "Second\n" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await editor.snapshot() == "Second\n")
    }

    @Test func imageAttachmentsStayBetweenTheirSurroundingText() throws {
        let first = makePNG()
        let second = makePNG()
        let item = try MemoClipboard.item(text: "Before First Middle Second After", html: "<p>Before<img src='data:image/png;base64,a' alt='Look > here'>Middle<img src='data:image/png;base64,b' title='Second > image'>After</p>", images: [
            ["bytesBase64": first.base64EncodedString(), "mimeType": "image/png"],
            ["bytesBase64": second.base64EncodedString(), "mimeType": "image/png"],
        ])
        let rtfd = try #require(item.data(forType: .rtfd))
        let rich = try NSAttributedString(data: rtfd, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        #expect(rich.string.contains("Before\u{FFFC}Middle\u{FFFC}After"))
        var bytes: [Data] = []
        rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment, let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents { bytes.append(data) }
        }
        #expect(bytes == [first, second])
    }

    @Test func aFailedClipboardWriteRestoresPreviousRepresentations() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let previous = NSPasteboardItem()
        previous.setString("Keep the clipboard", forType: .string)
        previous.setString("<strong>Keep the clipboard</strong>", forType: .html)
        let image = makePNG()
        previous.setData(image, forType: .png)
        #expect(pasteboard.writeObjects([previous]))
        let next = NSPasteboardItem()
        next.setString("Replacement", forType: .string)
        #expect(throws: (any Error).self) { try MemoClipboard.write(next, to: pasteboard, writing: { _ in false }) }
        #expect(pasteboard.string(forType: .string) == "Keep the clipboard")
        #expect(pasteboard.string(forType: .html) == "<strong>Keep the clipboard</strong>")
        #expect(pasteboard.data(forType: .png) == image)
    }

    @Test func nativeRichImagePasteKeepsSemanticHTMLInsteadOfCocoaHeaders() async throws {
        let bytes = makePNG()
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = FolderImageStore(besideStoreAt: folder.appending(path: "store.json"))
        let hash = try await images.save(bytes).path
        let editor = EditorController(images: images)
        editor.documentID = "fixture"
        editor.load("")
        _ = try await editor.snapshot()
        let second = makePNG()
        let secondHash = try await images.save(second).path
        let html = "<h1>Heading</h1><p><strong>Before</strong> <img alt='Picture' title='First image' src='file:///transport/first.png'> Middle <img alt='Second' src='cid:second'> After</p><table><tr><th>Name</th><th>Value</th></tr><tr><td>Alpha</td><td>42</td></tr></table>"
        let item = try MemoClipboard.item(text: "Heading Before Picture After Name Value Alpha 42", html: html, images: [
            ["bytesBase64": bytes.base64EncodedString(), "mimeType": "image/png"],
            ["bytesBase64": second.base64EncodedString(), "mimeType": "image/png"],
        ])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([item]))
        var source = ""
        editor.onChanged = { source = $0 }
        #expect(editor.pasteCapturedClipboard(from: pasteboard))
        for _ in 0..<200 {
            if source.contains(hash), source.contains(secondHash) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(source.contains("# Heading"))
        #expect(source.contains("**Before**"))
        #expect(source.contains(hash))
        #expect(source.contains("![Picture](\(hash) \"First image\")"))
        #expect(source.contains("![Second](\(secondHash))"))
        let firstRange = try #require(source.range(of: hash))
        let middleRange = try #require(source.range(of: "Middle"))
        let secondRange = try #require(source.range(of: secondHash))
        #expect(firstRange.lowerBound < middleRange.lowerBound && middleRange.lowerBound < secondRange.lowerBound)
        #expect(!source.contains("file:///transport"))
        #expect(!source.contains("cid:second"))
        #expect(source.range(of: #"\|\s*Alpha\s*\|\s*42\s*\|"#, options: .regularExpression) != nil)
        #expect(!source.contains("<style"))
        #expect(!source.contains("Cocoa HTML Writer"))
        #expect(try Data(contentsOf: try #require(await images.url(for: hash))) == bytes)
        #expect(try Data(contentsOf: try #require(await images.url(for: secondHash))) == second)
    }

    @Test func mismatchedRichAttachmentsDoNotReplaceHTMLSources() throws {
        let html = "<h2>Heading</h2><img src='cid:first' alt='First'><img src='file:///second.png' alt='Second'>"
        let attachments = [["source": "data:image/png;base64,available"]]
        #expect(try MemoClipboard.replacingImageSources(in: html, attachments: attachments) == nil)
        let quoted = "<img alt=\"Use src='preview'\" data-src='hint' src='cid:first' title='Image'>"
        #expect(try MemoClipboard.replacingImageSources(in: quoted, attachments: attachments) == "<img alt=\"Use src='preview'\" data-src='hint' src=\"data:image/png;base64,available\" title='Image'>")
    }

    @Test func rtfdOnlyPasteKeepsEmphasisAndOrderedImageBytesWithoutGeneratedHeaders() async throws {
        let first = makePNG()
        let second = makePNG()
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = FolderImageStore(besideStoreAt: folder.appending(path: "store.json"))
        let hashes = [try await images.save(first).path, try await images.save(second).path]
        let editor = EditorController(images: images)
        editor.documentID = "fixture"
        editor.load("")
        _ = try await editor.snapshot()
        let rich = try MemoClipboard.item(text: "Before Middle After", html: "<p><strong>Before</strong><img src='data:image/png;base64,a'>Middle<img src='data:image/png;base64,b'>After</p>", images: [
            ["bytesBase64": first.base64EncodedString(), "mimeType": "image/png"],
            ["bytesBase64": second.base64EncodedString(), "mimeType": "image/png"],
        ])
        let item = NSPasteboardItem()
        item.setData(try #require(rich.data(forType: .rtfd)), forType: .rtfd)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([item]))
        var source = ""
        editor.onChanged = { source = $0 }
        #expect(editor.pasteCapturedClipboard(from: pasteboard))
        for _ in 0..<200 {
            if hashes.allSatisfy(source.contains) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(source.contains("**Before**"))
        let firstRange = try #require(source.range(of: hashes[0]))
        let middleRange = try #require(source.range(of: "Middle"))
        let secondRange = try #require(source.range(of: hashes[1]))
        let afterRange = try #require(source.range(of: "After"))
        #expect(firstRange.lowerBound < middleRange.lowerBound)
        #expect(middleRange.lowerBound < secondRange.lowerBound)
        #expect(secondRange.lowerBound < afterRange.lowerBound)
        #expect(!source.contains("<style"))
        #expect(!source.contains("Cocoa HTML Writer"))
        #expect(try Data(contentsOf: try #require(await images.url(for: hashes[0]))) == first)
        #expect(try Data(contentsOf: try #require(await images.url(for: hashes[1]))) == second)
    }

    @Test func rtfdTIFFAttachmentBecomesAPortablePNGWithoutLosingText() async throws {
        let png = makePNG()
        let bitmap = try #require(NSBitmapImageRep(data: png))
        let tiff = try #require(bitmap.tiffRepresentation)
        #expect(ImageType(sniffing: tiff) == nil)
        let converted = try #require(MemoClipboard.supportedImage(tiff))
        #expect(converted.type == .png)
        let rich = NSMutableAttributedString(string: "Before\u{FFFC}After")
        let wrapper = FileWrapper(regularFileWithContents: tiff)
        wrapper.preferredFilename = "fixture.tiff"
        rich.replaceCharacters(in: NSRange(location: 6, length: 1), with: NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
        let item = NSPasteboardItem()
        item.setData(try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]), forType: .rtfd)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([item]))
        let folder = try temporaryFolder()
        defer { discard(folder) }
        let images = FolderImageStore(besideStoreAt: folder.appending(path: "store.json"))
        let reference = try await images.save(converted.bytes).path
        let editor = EditorController(images: images)
        editor.documentID = "fixture"
        editor.load("")
        _ = try await editor.snapshot()
        var source = ""
        editor.onChanged = { source = $0 }
        #expect(editor.pasteCapturedClipboard(from: pasteboard))
        for _ in 0..<200 {
            if source.contains(reference) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(source.contains("Before"))
        #expect(source.contains(reference))
        #expect(source.contains("After"))
        #expect(!source.contains("Cocoa HTML Writer"))
        let stored = try Data(contentsOf: try #require(await images.url(for: reference)))
        #expect(stored == converted.bytes)
        #expect(ImageType(sniffing: stored) == .png)
    }
}

private actor SuspendedImageStore: ImageStore {
    private var continuation: CheckedContinuation<ImageReference, any Error>?
    private var reference: ImageReference?
    private let backing: (any ImageStore)?
    init(backing: (any ImageStore)? = nil) { self.backing = backing }
    var isSaving: Bool { continuation != nil }
    func save(_ data: Data) async throws -> ImageReference {
        reference = try await backing?.save(data) ?? ImageReference(path: "images/" + String(repeating: "a", count: 64) + ".png")
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete() {
        if let reference { continuation?.resume(returning: reference) }
        continuation = nil
        reference = nil
    }
    func url(for path: String) async -> URL? { await backing?.url(for: path) }
    func removeOrphans(keeping used: Set<String>) {}
}

@MainActor
private func makePNG() -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for index in 0..<(bitmap.bytesPerRow * bitmap.pixelsHigh) { bitmap.bitmapData![index] = index % 4 == 3 ? 255 : .random(in: 0...255) }
    return bitmap.representation(using: .png, properties: [:])!
}
