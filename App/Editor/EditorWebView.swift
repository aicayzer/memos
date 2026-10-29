import AppKit
import WebKit

/// The web view takes file drops itself: the page never sees a dropped file's path, and a file
/// dropped on a memo should read as its path.
final class EditorWebView: WKWebView {
    var onPaste: () -> Bool = { false }
    var onInputActivity: () -> Void = {}
    var onFocusActivity: (Bool) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        onInputActivity()
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusActivity(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusActivity(false) }
        return accepted
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Key equivalents traverse every subview, including editors that do not own the keyboard.
        guard ownsFirstResponder(in: NSApp.keyWindow) else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v", onPaste() { return true }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any?) {
        guard ownsFirstResponder(in: NSApp.keyWindow) else { return }
        if !onPaste() { NSSound.beep() }
    }

    var onDropFiles: ([URL], CGPoint) -> Void = { _, _ in }

    private static let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    private func fileURLs(in sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: Self.readingOptions) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileURLs(in: sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileURLs(in: sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(in: sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onDropFiles(urls, mirrored(convert(sender.draggingLocation, from: nil)))
        return true
    }

    /// The page measures from the top; the web view happens to as well, which nothing documents.
    func mirrored(_ point: CGPoint) -> CGPoint {
        isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
