import AppKit

/// What the app needs of the editor. The window's own editor is a web view behind it; a test stands
/// something simpler in its place, so saving, history and memo switching can be driven without a window.
@MainActor
protocol Editing: AnyObject {
    /// The marks and block under the caret, for the formatting bar.
    var caret: CaretState { get }

    var onChanged: (String) -> Void { get set }
    var onOpenLink: (URL) -> Void { get set }
    var onCopy: (String) -> Void { get set }
    /// Files dropped on the memo, and where they landed.
    var onDropFiles: ([URL], CGPoint) -> Void { get set }
    /// An image was pasted; its bytes are on the pasteboard.
    var onPasteImage: () -> Void { get set }

    var accentOverride: NSColor? { get set }
    var textSize: Double { get set }
    var keymap: [String: [String]] { get set }

    /// Shows the markdown, with the caret at the end: another memo, or this one again.
    func load(_ markdown: String)
    /// Shows the markdown of the memo already open, keeping the caret and the scroll where they are.
    func reload(_ markdown: String)
    func format(_ command: FormatCommand, argument: String?)
    func focus()
    func find(_ text: String)
    /// Inserts the paths as lines at a point in the view.
    func insertPaths(_ paths: [String], at point: CGPoint)
    /// Inserts the images as blocks at a point in the view, or at the caret when there is none.
    func insertImages(_ references: [ImageReference], at point: CGPoint?)
    /// The document as markdown, or nil while it is still what was loaded.
    func markdown() async -> String?

    /// The view the memo is drawn in.
    var contentView: NSView { get }
}

extension Editing {
    func format(_ command: FormatCommand) {
        format(command, argument: nil)
    }
}
