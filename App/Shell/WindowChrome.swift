import AppKit

/// The system window buttons, kept: hidden while the window is not key, dimmed until the pointer reaches them.
@MainActor
final class WindowChrome: NSResponder {
    private weak var window: NSWindow?
    private var buttons: [NSButton] = []

    private static let dimmed: CGFloat = 0.45

    override init() {
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

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

        buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        buttons.first?.superview?.addTrackingArea(NSTrackingArea(
            rect: hoverRect, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self
        ))
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(update), name: name, object: window)
        }
        update()
    }

    private var hoverRect: NSRect {
        buttons.map(\.frame).reduce(NSRect.null) { $0.union($1) }.insetBy(dx: -6, dy: -6)
    }

    // Read from the pointer rather than the event, since an exit can go missing when the pointer warps.
    @objc private func update() {
        guard let window, let container = buttons.first?.superview else { return }
        let key = window.isKeyWindow
        let pointer = container.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hovering = key && hoverRect.contains(pointer)
        for button in buttons {
            button.isHidden = !key
            button.alphaValue = hovering ? 1 : Self.dimmed
        }
    }

    override func mouseEntered(with event: NSEvent) {
        update()
    }

    override func mouseExited(with event: NSEvent) {
        update()
    }
}
