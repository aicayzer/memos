import AppKit
import SwiftUI

/// The memo window is a panel that takes the keyboard without activating the app, as a launcher's
/// does: the app in front stays in front, its name stays in the menu bar, and typing lands here.
final class MemoPanel: NSPanel {
    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        // A panel hides with its app by default; this one is the app.
        hidesOnDeactivate = false
        let hosting = NSHostingView(rootView: content)
        // The content's minimum becomes the window's, so it follows the side pane.
        hosting.sizingOptions = [.minSize]
        contentView = hosting
        if !setFrameUsingName(Self.frameName) { center() }
        setFrameAutosaveName(Self.frameName)
    }

    /// A menu item carries one key; a shortcut's other keys are matched here. Before the content, since the
    /// web view claims every Command chord and turns some, ⌘. among them, into commands that never come back.
    var alternates: () -> [(key: KeyCombo, shortcut: Shortcut)] = { [] }
    var perform: (Shortcut) -> Void = { _ in }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let pressed = KeyCombo(event: event), let match = alternates().first(where: { $0.key == pressed }) {
            perform(match.shortcut)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static let frameName = "main"
}
