import AppKit
import SwiftUI
import Testing
@testable import Memos

@MainActor
@Suite(.serialized)
struct OverlayFocusTests {
    private final class FocusPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    @MainActor
    private final class Query {
        var text = ""
        var binding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
    }

    private func panel() -> NSPanel {
        let panel = FocusPanel(contentRect: NSRect(x: 100, y: 100, width: 480, height: 300),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        return panel
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    private func field(in panel: NSPanel, current: @escaping () -> Bool = { true }) -> OverlayTextField {
        let field = OverlayTextField(frame: NSRect(x: 20, y: 230, width: 300, height: 28))
        field.isCurrent = current
        panel.contentView!.addSubview(field)
        return field
    }

    private func mainQueueBoundary() async {
        // AppKit attachment schedules one focus transfer on the main queue.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func searchField(in view: NSView) -> OverlayTextField? {
        if let field = view as? OverlayTextField { return field }
        for child in view.subviews {
            if let field = searchField(in: child) { return field }
        }
        return nil
    }

    private func sendLetter(_ letter: String, keyCode: UInt16, to panel: NSPanel) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, characters: letter,
            charactersIgnoringModifiers: letter, isARepeat: false, keyCode: keyCode
        ))
        panel.sendEvent(event)
    }

    @Test func inputBeforeFieldAttachmentReachesQueryInsteadOfMemo() async throws {
        let panel = MemoPanel(content: EmptyView(), restoresFrame: false)
        panel.setFrameAutosaveName("")
        defer { close(panel) }
        panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        let memo = NSTextView(frame: NSRect(x: 20, y: 20, width: 300, height: 150))
        memo.string = "Unchanged memo"
        panel.contentView!.addSubview(memo)
        panel.makeKeyAndOrderFront(nil)
        #expect(panel.makeFirstResponder(memo))
        panel.prepareOverlayFocus()
        #expect(panel.firstResponder is OverlayInputResponder)
        try sendLetter("b", keyCode: 11, to: panel)
        try sendLetter("r", keyCode: 15, to: panel)
        #expect(memo.string == "Unchanged memo")

        let query = Query()
        let view = OverlaySearchField(placeholder: "Commands", text: query.binding,
                                      isCurrent: { true }, submit: {}, dismiss: {})
        let coordinator = view.makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }
        let field = field(in: panel)
        field.delegate = coordinator
        await mainQueueBoundary()
        #expect(query.text == "br")
        #expect(panel.firstResponder === field.currentEditor())
        try sendLetter("o", keyCode: 31, to: panel)
        #expect(query.text == "bro")
        #expect(memo.string == "Unchanged memo")
    }

    @Test(arguments: [true, false])
    func discardedPendingInputDoesNotReachReplacement(resigningKey: Bool) async throws {
        let panel = MemoPanel(content: EmptyView(), restoresFrame: false)
        panel.setFrameAutosaveName("")
        let other = self.panel()
        defer { close(panel); close(other) }
        panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        panel.makeKeyAndOrderFront(nil)
        panel.prepareOverlayFocus()
        try sendLetter("b", keyCode: 11, to: panel)
        if resigningKey {
            other.makeKeyAndOrderFront(nil)
            #expect(!panel.isKeyWindow)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.cancelPendingOverlayInput()
        }

        let query = Query()
        let view = OverlaySearchField(placeholder: "Search memos", text: query.binding,
                                      isCurrent: { true }, submit: {}, dismiss: {})
        let coordinator = view.makeCoordinator()
        defer { withExtendedLifetime(coordinator) {} }
        let replacement = field(in: panel)
        replacement.delegate = coordinator
        await mainQueueBoundary()
        #expect(query.text.isEmpty)
        #expect(panel.firstResponder === replacement.currentEditor())
        try sendLetter("r", keyCode: 15, to: panel)
        #expect(query.text == "r")
    }

    @Test func attachedFieldTakesActualFirstResponderFromMemo() async throws {
        let panel = panel()
        defer { close(panel) }
        let memo = NSTextView(frame: NSRect(x: 20, y: 20, width: 300, height: 150))
        memo.string = "Unchanged memo"
        panel.contentView!.addSubview(memo)
        panel.makeKeyAndOrderFront(nil)
        #expect(panel.makeFirstResponder(memo))

        let field = field(in: panel)
        await mainQueueBoundary()
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(panel.firstResponder === editor)
        #expect(field.hasFocused)
        editor.insertText("query", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(field.stringValue == "query")
        #expect(memo.string == "Unchanged memo")
    }

    @Test func detachedRequestCannotDisplaceReplacement() async throws {
        let panel = panel()
        defer { close(panel) }
        panel.makeKeyAndOrderFront(nil)
        let obsolete = field(in: panel)
        obsolete.removeFromSuperview()
        obsolete.cancelFocus()
        let replacement = field(in: panel)

        await mainQueueBoundary()
        let editor = try #require(replacement.currentEditor())
        #expect(panel.firstResponder === editor)
        #expect(!obsolete.hasFocused)
        #expect(replacement.hasFocused)
        obsolete.requestInitialFocus()
        await mainQueueBoundary()
        #expect(panel.firstResponder === editor)
    }

    @Test func supersededAttachedRequestCannotTakeFocus() async throws {
        let panel = panel()
        defer { close(panel) }
        panel.makeKeyAndOrderFront(nil)
        var isCurrent = true
        let obsolete = field(in: panel, current: { isCurrent })
        isCurrent = false
        let replacement = field(in: panel)

        await mainQueueBoundary()
        #expect(!obsolete.hasFocused)
        #expect(panel.firstResponder === replacement.currentEditor())
        #expect(replacement.hasFocused)
    }

    @Test func fieldWaitsUntilItsOwnWindowBecomesKey() async throws {
        let background = panel()
        let foreground = panel()
        defer { close(background); close(foreground) }
        background.orderFront(nil)
        foreground.makeKeyAndOrderFront(nil)
        let foregroundEditor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        foreground.contentView!.addSubview(foregroundEditor)
        #expect(foreground.makeFirstResponder(foregroundEditor))
        let field = field(in: background)

        await mainQueueBoundary()
        #expect(!field.hasFocused)
        #expect(foreground.firstResponder === foregroundEditor)
        background.makeKeyAndOrderFront(nil)
        await mainQueueBoundary()
        #expect(field.hasFocused)
        #expect(background.firstResponder === field.currentEditor())
    }

    @Test func hostedPaletteFocusAndSelectionSurviveResultsRefresh() async throws {
        let panel = panel()
        defer { close(panel) }
        let memo = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        memo.string = "Memo stays untouched"
        panel.contentView!.addSubview(memo)
        panel.makeKeyAndOrderFront(nil)
        #expect(panel.makeFirstResponder(memo))
        let query = Query()
        func palette(_ items: [PaletteItem]) -> PaletteView {
            PaletteView(placeholder: "Search memos", items: items, query: query.binding,
                        isCurrent: { true }, dismiss: {}, dismissForAction: {})
        }
        let host = NSHostingView(rootView: palette([PaletteItem(id: "first", title: "First", action: {})]))
        host.frame = NSRect(x: 20, y: 80, width: 420, height: 200)
        panel.contentView!.addSubview(host)
        host.layoutSubtreeIfNeeded()
        await mainQueueBoundary()
        let original = try #require(searchField(in: host))
        let editor = try #require(original.currentEditor() as? NSTextView)
        #expect(panel.firstResponder === editor)
        editor.insertText("query", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(query.text == "query")
        editor.setSelectedRange(NSRange(location: 2, length: 1))

        host.rootView = palette([PaletteItem(id: "updated", title: "Updated result", action: {})])
        host.layoutSubtreeIfNeeded()
        await mainQueueBoundary()
        #expect(searchField(in: host) === original)
        #expect(panel.firstResponder === editor)
        #expect(editor.selectedRange() == NSRange(location: 2, length: 1))
        #expect(query.text == "query")
        #expect(memo.string == "Memo stays untouched")
    }

    @Test func queuedBlurCannotDismissReplacementOverlay() async throws {
        let panel = panel()
        defer { close(panel) }
        panel.makeKeyAndOrderFront(nil)
        let query = Query()
        var current: String? = "palette"
        var dismissals: [String] = []
        let oldView = OverlaySearchField(placeholder: "Commands", text: query.binding,
                                         isCurrent: { current == "palette" }, submit: {}, dismiss: {},
                                         blur: { dismissals.append("palette"); current = nil })
        let coordinator = oldView.makeCoordinator()
        let obsolete = field(in: panel, current: { current == "palette" })
        await mainQueueBoundary()
        #expect(obsolete.hasFocused)
        #expect(panel.makeFirstResponder(nil))
        #expect(obsolete.currentEditor() == nil)
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification,
                                                          object: obsolete))

        // SwiftUI can update a representable's coordinator before its old blur callback runs.
        current = "browse"
        coordinator.parent = OverlaySearchField(placeholder: "Search memos", text: query.binding,
                                                isCurrent: { current == "browse" }, submit: {}, dismiss: {},
                                                blur: { dismissals.append("browse"); current = nil })
        let replacement = field(in: panel, current: { current == "browse" })
        await mainQueueBoundary()
        #expect(current == "browse")
        #expect(dismissals.isEmpty)
        #expect(replacement.hasFocused)
        #expect(panel.firstResponder === replacement.currentEditor())
    }

    @Test(arguments: [true, false])
    func paletteActionRestoresEditorOnlyWhenRequested(restoresEditor: Bool) async throws {
        let panel = panel()
        defer { close(panel) }
        panel.makeKeyAndOrderFront(nil)
        let query = Query()
        var events: [String] = []
        let item = PaletteItem(id: "action", title: "Action", restoresEditor: restoresEditor,
                               action: { events.append("action") })
        let host = NSHostingView(rootView: PaletteView(
            placeholder: "Commands", items: [item], query: query.binding, isCurrent: { true },
            dismiss: { events.append("escape") }, dismissForAction: { events.append("dismiss") },
            restoreEditor: { events.append("restore") }
        ))
        host.frame = NSRect(x: 20, y: 80, width: 420, height: 200)
        panel.contentView!.addSubview(host)
        host.layoutSubtreeIfNeeded()
        await mainQueueBoundary()
        let field = try #require(searchField(in: host))
        let editor = try #require(field.currentEditor() as? NSTextView)
        let coordinator = try #require(field.delegate as? OverlaySearchField.Coordinator)
        #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(events == (restoresEditor ? ["dismiss", "action", "restore"] : ["dismiss", "action"]))
    }

    @Test func commandsRouteOnlyWhileOverlayOwnsFocus() {
        let query = Query()
        var current = true
        var submitted = 0
        var dismissed = 0
        var moves: [Int] = []
        let view = OverlaySearchField(placeholder: "Search", text: query.binding, isCurrent: { current },
                                      submit: { submitted += 1 }, dismiss: { dismissed += 1 },
                                      move: { moves.append($0) })
        let coordinator = view.makeCoordinator()
        let field = OverlayTextField()
        let editor = NSTextView()
        #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(moves == [1, -1])
        #expect(submitted == 1)
        #expect(dismissed == 1)
        #expect(!coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))

        current = false
        #expect(!coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        field.stringValue = "obsolete query"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(submitted == 1)
        #expect(query.text.isEmpty)
    }
}
