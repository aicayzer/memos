import AppKit
import SwiftUI

/// In a nonactivating AppKit panel, SwiftUI's initial focus request can leave the editor as
/// first responder. Transfer focus only after this field belongs to the key window.
struct OverlaySearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 15
    let isCurrent: () -> Bool
    let submit: () -> Void
    let dismiss: () -> Void
    var move: ((Int) -> Void)?
    var blur: (() -> Void)?

    func makeNSView(context: Context) -> OverlayTextField {
        let field = OverlayTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        updateNSView(field, context: context)
        return field
    }

    func updateNSView(_ field: OverlayTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        field.font = .systemFont(ofSize: fontSize)
        field.isCurrent = isCurrent
        if field.stringValue != text { field.stringValue = text }
        field.requestInitialFocus()
    }

    static func dismantleNSView(_ field: OverlayTextField, coordinator: Coordinator) {
        field.cancelFocus()
        field.delegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OverlaySearchField
        init(_ parent: OverlaySearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, parent.isCurrent() else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard parent.isCurrent() else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.dismiss()
            case #selector(NSResponder.moveUp(_:)):
                guard let move = parent.move else { return false }
                move(-1)
            case #selector(NSResponder.moveDown(_:)):
                guard let move = parent.move else { return false }
                move(1)
            default: return false
            }
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? OverlayTextField else { return }
            let owner = parent
            // A clicked result or a replacement overlay gets to finish before handling an outside click.
            DispatchQueue.main.async { [weak field] in
                guard let field, field.window?.isKeyWindow == true,
                      field.currentEditor() == nil, field.hasFocused, owner.isCurrent() else { return }
                owner.blur?()
            }
        }
    }
}

final class OverlayTextField: NSTextField {
    var isCurrent: () -> Bool = { false }
    private(set) var hasFocused = false
    private var generation = 0
    private var scheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        generation += 1
        scheduled = false
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
            requestInitialFocus()
        }
    }

    @objc private func windowBecameKey() { requestInitialFocus() }

    func requestInitialFocus() {
        guard !hasFocused, !scheduled, window != nil, isCurrent() else { return }
        scheduled = true
        let request = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, request == self.generation else { return }
            self.scheduled = false
            guard !self.hasFocused, self.isCurrent(), let window = self.window, window.isKeyWindow else { return }
            let pending = window.firstResponder as? OverlayInputResponder
            self.hasFocused = window.makeFirstResponder(self)
            if self.hasFocused {
                for event in pending?.takeEvents() ?? [] {
                    guard self.isCurrent(), window.isKeyWindow else { break }
                    window.sendEvent(event)
                }
            }
        }
    }

    func cancelFocus() {
        generation += 1
        scheduled = false
        isCurrent = { false }
        NotificationCenter.default.removeObserver(self)
    }
}

/// SwiftUI mounts the field after the shortcut returns. Keep those first keystrokes out of the memo.
final class OverlayInputResponder: NSResponder {
    private var events: [NSEvent] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { events.append(event) }
    func discardEvents() { events.removeAll() }
    func takeEvents() -> [NSEvent] {
        defer { discardEvents() }
        return events
    }
}
