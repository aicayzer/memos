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

    private static let frameName = "main"
}
