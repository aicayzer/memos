import AppKit

/// Image tokens keep attachment positions independent of the HTML importer's data-URL support.
@MainActor
enum MemoClipboard {
    static func supportedImage(_ data: Data) -> (bytes: Data, type: ImageType)? {
        if let type = ImageType(sniffing: data) { return (data, type) }
        guard let tiff = NSImage(data: data)?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return (png, .png)
    }

    /// Only ordered RTFD attachments establish an association with HTML images; preview bitmaps do not.
    static func replacingImageSources(in html: String, attachments: [[String: String]]) throws -> String? {
        let pattern = try NSRegularExpression(pattern: "<img\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>", options: [.caseInsensitive])
        let matches = pattern.matches(in: html, range: NSRange(location: 0, length: (html as NSString).length))
        guard matches.count == attachments.count else { return nil }
        let attributes = try NSRegularExpression(pattern: "\\s+([^\\s=/>]+)(?:\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]+))?")
        var result = html
        for (index, match) in matches.enumerated().reversed() {
            guard let source = attachments[index]["source"] else { return nil }
            let tag = (html as NSString).substring(with: match.range)
            let replacement: String
            if let attribute = attributes.matches(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)).first(where: {
                (tag as NSString).substring(with: $0.range(at: 1)).lowercased() == "src"
            }) {
                replacement = (tag as NSString).replacingCharacters(in: attribute.range, with: " src=\"\(source)\"")
            } else {
                let prefix = String(tag.dropLast())
                replacement = (prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix) + " src=\"\(source)\">"
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    /// Cocoa's document metadata describes transport, not content. Inline its styles before importing the body.
    static func formattedHTML(from rich: NSAttributedString) throws -> String {
        let data = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        let document = String(decoding: data, as: UTF8.self)
        let original = document as NSString
        let bodyPattern = try NSRegularExpression(pattern: "<body\\b[^>]*>([\\s\\S]*?)</body>", options: [.caseInsensitive])
        guard let body = bodyPattern.firstMatch(in: document, range: NSRange(location: 0, length: original.length)) else {
            throw MemoClipboardError.unavailable("Couldn’t read formatted text.")
        }
        let stylePattern = try NSRegularExpression(pattern: "[a-z]+\\.([a-zA-Z0-9_-]+)\\s*\\{([^}]+)\\}")
        var styles: [String: String] = [:]
        for match in stylePattern.matches(in: document, range: NSRange(location: 0, length: body.range.location)) {
            styles[original.substring(with: match.range(at: 1))] = original.substring(with: match.range(at: 2))
        }
        var html = original.substring(with: body.range(at: 1))
        let classes = try NSRegularExpression(pattern: "class=\"([^\"]+)\"")
        for match in classes.matches(in: html, range: NSRange(location: 0, length: (html as NSString).length)).reversed() {
            let names = (html as NSString).substring(with: match.range(at: 1)).split(separator: " ")
            let css = names.compactMap { styles[String($0)] }.joined(separator: "; ")
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            html = (html as NSString).replacingCharacters(in: match.range, with: "style=\"\(css)\"")
        }
        // Cocoa inserts layout whitespace between tags. Keep authored text inside those tags intact.
        return html.replacingOccurrences(of: ">\\s*\\n\\s*<", with: "><", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ item: NSPasteboardItem, to pasteboard: NSPasteboard, writing: (([NSPasteboardItem]) -> Bool)? = nil) throws {
        let previous = (pasteboard.pasteboardItems ?? []).map { original in
            let saved = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { saved.setData(data, forType: type) }
            }
            return saved
        }
        pasteboard.clearContents()
        guard (writing ?? { pasteboard.writeObjects($0) })([item]) else {
            pasteboard.clearContents()
            if !previous.isEmpty, !pasteboard.writeObjects(previous) {
                throw MemoClipboardError.unavailable("Couldn’t restore the clipboard. Your text is still open.")
            }
            throw MemoClipboardError.unavailable("Couldn’t write the clipboard. The previous clipboard was restored.")
        }
    }

    static func item(text: String, html: String, images: [[String: String]]) throws -> NSPasteboardItem {
        let pattern = try NSRegularExpression(pattern: "<img\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>", options: [.caseInsensitive])
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
