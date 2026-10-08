import AppKit
import Testing
@testable import Memos

@MainActor
@Suite(.serialized, .opensWindows)
struct InkKitBridgeTests {
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
        let item = try MemoClipboard.item(text: "Before First Middle Second After", html: "<p>Before<img src='data:image/png;base64,a'>Middle<img src='data:image/png;base64,b'>After</p>", images: [
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
}

private actor SuspendedImageStore: ImageStore {
    private var continuation: CheckedContinuation<ImageReference, any Error>?
    var isSaving: Bool { continuation != nil }
    func save(_ data: Data) async throws -> ImageReference {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete() {
        continuation?.resume(returning: ImageReference(path: "images/" + String(repeating: "a", count: 64) + ".png"))
        continuation = nil
    }
    func url(for path: String) -> URL? { nil }
    func removeOrphans(keeping used: Set<String>) {}
}

@MainActor
private func makePNG() -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for index in 0..<(bitmap.bytesPerRow * bitmap.pixelsHigh) { bitmap.bitmapData![index] = index % 4 == 3 ? 255 : .random(in: 0...255) }
    return bitmap.representation(using: .png, properties: [:])!
}
