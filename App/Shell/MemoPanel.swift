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

    /// The app's shortcuts, matched here before the content, since the web view claims every Command chord
    /// and turns some into editing commands that never come back: ⌘. and ⌘⌫ among them. The menu is offered
    /// the event first, so a key it answers never reaches this.
    var keys: () -> [(key: KeyCombo, shortcut: Shortcut)] = { [] }
    var perform: (Shortcut) -> Void = { _ in }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let pressed = KeyCombo(event: event), let match = keys().first(where: { $0.key == pressed }) {
            perform(match.shortcut)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static let frameName = "main"
}
