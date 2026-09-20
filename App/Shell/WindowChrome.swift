import AppKit

/// The system window buttons and window shape: close stays live and red, minimize and zoom are
/// disabled, and all three hide while the window is not key.
@MainActor
final class WindowChrome: NSObject {
    private weak var window: NSWindow?
    private var buttons: [NSButton] = []

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        // An empty unified toolbar gives the tall title bar the buttons are centered in.
        let toolbar = NSToolbar()
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // The backdrop draws the rounder shape; the window itself paints nothing.
        window.isOpaque = false
        window.backgroundColor = .clear

        buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(update), name: name, object: window)
        }
        update()
    }

    @objc private func update() {
        let key = window?.isKeyWindow == true
        for button in buttons { button.isHidden = !key }
    }
}
