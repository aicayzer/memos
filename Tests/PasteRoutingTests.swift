import AppKit
import Testing
@testable import Memos

@MainActor
@Suite(.serialized, .opensWindows)
struct PasteRoutingTests {
    private final class PastePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private func preserveClipboard() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { original in
            let saved = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { saved.setData(data, forType: type) }
            }
            return saved
        }
    }

    private func attach(_ editor: EditorController) -> (PastePanel, NSTextField) {
        let window = PastePanel(contentRect: NSRect(x: 100, y: 100, width: 500, height: 600),
                                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content
        editor.webView.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        content.addSubview(editor.webView)
        let field = NSTextField(frame: NSRect(x: 20, y: 520, width: 250, height: 28))
        content.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        return (window, field)
    }

    private func mainQueueBoundary() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test(arguments: [false, true], [false, true])
    func blockMovesLeaveNativeFieldsAlone(up: Bool, focusChangesAfterQueueing: Bool) async throws {
        let editor = EditorController(images: FakeImageStore())
        let (window, field) = attach(editor)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let source = "First\n\nMiddle\n\nLast\n"
        editor.documentID = "moving"
        editor.load(source)
        _ = try await editor.snapshot()
        editor.focus()
        _ = try await editor.webView.evaluateJavaScript("window.editor.find('Middle', 1)")
        for _ in 0..<200 {
            if editor.caret.commands[up ? "moveBlockUp" : "moveBlockDown"] == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(editor.caret.commands[up ? "moveBlockUp" : "moveBlockDown"] == true)
        field.stringValue = "Keep the field text"
        if !focusChangesAfterQueueing { #expect(window.makeFirstResponder(field)) }
        editor.moveBlock(up: up)
        if focusChangesAfterQueueing { #expect(window.makeFirstResponder(field)) }
        await mainQueueBoundary()
        #expect(try await editor.snapshot() == source)
        #expect(field.stringValue == "Keep the field text")
        #expect(window.firstResponder === field.currentEditor())
    }

    @Test(arguments: ["Search memos", "Title"], [false, true])
    func pasteReplacesTheFocusedNativeField(fieldName: String, plainText: Bool) async throws {
        let previousClipboard = preserveClipboard()
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(previousClipboard)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Replacement", forType: .string)
        let suite = "paste-routing-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let editor = EditorController(images: FakeImageStore())
        let model = AppModel(store: ChangeableStore([]), images: FakeImageStore(), defaults: defaults, editor: editor)
        let (window, field) = attach(editor)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        field.placeholderString = fieldName
        field.stringValue = "Selected field text"
        editor.documentID = "paste-target"
        editor.load("Unchanged memo\n")
        _ = try await editor.snapshot()
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        fieldEditor.selectAll(nil)
        #expect(window.firstResponder === fieldEditor)

        if plainText {
            model.pasteAsPlainText()
        } else {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9
            ))
            // The window gets the key equivalent before the standard Paste menu action.
            if !window.performKeyEquivalent(with: event) {
                #expect(NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil))
            }
        }
        #expect(try await editor.snapshot() == "Unchanged memo\n")
        #expect(field.stringValue == "Replacement")
        #expect(window.firstResponder === fieldEditor)
    }

    @Test(arguments: [false, true], [false, true])
    func queuedPasteCannotFollowFocusOrDocumentChanges(plainText: Bool, changesDocument: Bool) async throws {
        let editor = EditorController(images: FakeImageStore())
        let (window, field) = attach(editor)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        editor.documentID = "original"
        editor.load("Original memo\n")
        _ = try await editor.snapshot()
        editor.focus()
        _ = try await editor.snapshot()
        #expect(editor.webView.ownsFirstResponder(in: NSApp.keyWindow))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Must not be pasted", forType: .string)
        if plainText { editor.pasteAsPlainText("Must not be pasted") }
        else { #expect(editor.pasteCapturedClipboard(from: pasteboard, requiringFocus: true)) }
        if changesDocument {
            editor.documentID = "replacement"
            editor.load("Replacement memo\n")
        } else {
            field.stringValue = "Keep this field"
            #expect(window.makeFirstResponder(field))
        }
        await mainQueueBoundary()
        #expect(try await editor.snapshot() == (changesDocument ? "Replacement memo\n" : "Original memo\n"))
        if !changesDocument {
            #expect(field.stringValue == "Keep this field")
            #expect(window.firstResponder === field.currentEditor())
        }
    }

    @Test(arguments: [false, true], [false, true])
    func focusedEditorStillPastesText(plainText: Bool, sourceMode: Bool) async throws {
        let previousClipboard = preserveClipboard()
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(previousClipboard)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Pasted text", forType: .string)
        let editor = EditorController(images: FakeImageStore())
        let (window, _) = attach(editor)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        editor.documentID = "focused"
        editor.load("Before\n")
        _ = try await editor.snapshot()
        _ = try await editor.webView.evaluateJavaScript("window.editor.setEditingMode('\(sourceMode ? "source" : "formatted")', 1)")
        editor.focus()
        _ = try await editor.snapshot()
        #expect(editor.webView.ownsFirstResponder(in: NSApp.keyWindow))
        if plainText { editor.pasteAsPlainText("Pasted text") }
        else { editor.webView.paste(nil) }
        await mainQueueBoundary()
        #expect(try await editor.snapshot().contains("Pasted text"))
        #expect(editor.webView.ownsFirstResponder(in: NSApp.keyWindow))
    }
}
