import AppKit
import Testing
@testable import Memos

@MainActor
@Suite(.serialized)
struct FilenameInputTests {
    @Test func nativeEditingKeepsLiteralsAndInsertsAtCaret() async throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 440, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let input = FilenameInput(frame: NSRect(x: 10, y: 30, width: 400, height: 26))
        window.contentView?.addSubview(input)
        var parts: [TextPadNamePart] = [.literal("meeting, ")] + TextPadFilename.defaultParts
        input.changed = { parts = $0 }
        input.setParts(parts)
        defer { input.field.objectValue = []; input.field.delegate = nil }
        window.makeKeyAndOrderFront(nil)
        #expect(window.makeFirstResponder(input.field))
        let editor = try #require(input.field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        input.insert(.day)
        #expect(parts.prefix(3) == [.literal("meeting, "), .token(.day), .token(.year)])
        let current = try #require(input.field.currentEditor() as? NSTextView)
        #expect(current.selectedRange() == NSRange(location: 10, length: 0))
        let undo = try #require(current.undoManager)
        undo.undo()
        await nextMainQueueTurn()
        #expect(parts.prefix(2) == [.literal("meeting, "), .token(.year)])
        undo.redo()
        await nextMainQueueTurn()
        #expect(parts.prefix(3) == [.literal("meeting, "), .token(.day), .token(.year)])
        current.setSelectedRange(NSRange(location: 10, length: 0))
        current.insertText("-", replacementRange: current.selectedRange())
        await nextMainQueueTurn()
        #expect(parts.prefix(4) == [.literal("meeting, "), .token(.day), .literal("-"), .token(.year)])
        window.makeFirstResponder(nil)
        #expect(parts.contains(.token(.number)))
        #expect(parts.first == .literal("meeting, "))
    }
    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

}
