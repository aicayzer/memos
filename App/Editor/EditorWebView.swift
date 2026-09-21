import AppKit
import WebKit

/// The web view takes file drops itself: the page never sees a dropped file's path, and a file
/// dropped on a memo should read as its path.
final class EditorWebView: WKWebView {
    var onDropFiles: ([URL], CGPoint) -> Void = { _, _ in }

    private static let fileURLs: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    private func fileURLs(in sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: Self.fileURLs) as? [URL] ?? []
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
        var point = convert(sender.draggingLocation, from: nil)
        // The page measures from the top.
        if !isFlipped { point.y = bounds.height - point.y }
        onDropFiles(urls, point)
        return true
    }
}
