import AppKit

/// Image tokens keep attachment positions independent of the HTML importer's data-URL support.
@MainActor
enum MemoClipboard {
    static func item(text: String, html: String, images: [[String: String]]) throws -> NSPasteboardItem {
        let pattern = try NSRegularExpression(pattern: "<img\\b[^>]*>", options: [.caseInsensitive])
        let original = html as NSString
        let matches = pattern.matches(in: html, range: NSRange(location: 0, length: original.length))
        guard matches.count == images.count else { throw MemoClipboardError.unavailable("Couldn’t copy all image attachments. The clipboard is unchanged.") }
        var marked = html
        let nonce = UUID().uuidString
        for (index, match) in matches.enumerated().reversed() {
            marked = (marked as NSString).replacingCharacters(in: match.range, with: "INKKITIMAGE\(nonce)SLOT\(index)")
        }
        guard let data = marked.data(using: .utf8) else { throw MemoClipboardError.unavailable("Couldn’t copy formatted text.") }
        let rich = try NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        for (index, image) in images.enumerated() {
            guard let encoded = image["bytesBase64"], let bytes = Data(base64Encoded: encoded), let type = ImageType(sniffing: bytes) else {
                throw MemoClipboardError.unavailable("Couldn’t copy an image attachment. The clipboard is unchanged.")
            }
            let token = "INKKITIMAGE\(nonce)SLOT\(index)"
            let range = (rich.string as NSString).range(of: token)
            guard range.location != NSNotFound else { throw MemoClipboardError.unavailable("Couldn’t place an image attachment.") }
            let wrapper = FileWrapper(regularFileWithContents: bytes)
            wrapper.preferredFilename = "image-\(index).\(type.fileExtension)"
            let attachment = NSTextAttachment(fileWrapper: wrapper)
            rich.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
        }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(html, forType: .html)
        let range = NSRange(location: 0, length: rich.length)
        item.setData(try rich.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
        if !images.isEmpty {
            item.setData(try rich.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]), forType: .rtfd)
            if images.count == 1, let encoded = images[0]["bytesBase64"], let bytes = Data(base64Encoded: encoded), let type = ImageType(sniffing: bytes) {
                item.setData(bytes, forType: NSPasteboard.PasteboardType(type == .jpeg ? "public.jpeg" : "public.\(type.rawValue)"))
            }
        }
        return item
    }
}

enum MemoClipboardError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { switch self { case .unavailable(let message): message } }
}
