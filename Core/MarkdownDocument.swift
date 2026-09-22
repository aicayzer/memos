import Foundation

/// Only our single-line JSON flow mapping is interpreted. It is valid YAML; all other frontmatter
/// stays opaque so reading a note cannot reformat another application's metadata.
enum MarkdownDocument {
    private static let marker = "memos: "

    static func encode(_ memo: Memo) throws -> Data {
        var metadata = memo
        metadata.markdown = ""
        let object = try JSONSerialization.jsonObject(with: JSONMemoStore.encodeMemos([metadata])) as! [String: Any]
        var fields = (object["memos"] as! [[String: Any]])[0]
        fields.removeValue(forKey: "markdown")
        let header = String(decoding: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), as: UTF8.self)
        let (frontmatter, body, newline) = split(memo.markdown)
        let extra = frontmatter ?? ""
        return Data("---\(newline)\(marker)\(header)\(newline)\(extra)---\(newline)\(body)".utf8)
    }

    static func decode(_ data: Data, fallback: Memo) throws -> Memo {
        guard let text = String(data: data, encoding: .utf8) else {
            throw StorageError.invalid("A Markdown file is not valid UTF-8.")
        }
        let (frontmatter, body, newline) = split(text)
        guard let frontmatter else { var memo = fallback; memo.markdown = text; return memo }
        let lines = frontmatter.components(separatedBy: newline)
        let owned = lines.enumerated().filter { $0.element.hasPrefix(marker) }
        guard !owned.isEmpty else { var memo = fallback; memo.markdown = text; return memo }
        guard owned.count == 1, let line = owned.first else {
            throw StorageError.invalid("A Markdown file has duplicate Memos metadata.")
        }
        let json = Data(line.element.dropFirst(marker.count).utf8)
        guard var fields = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw StorageError.invalid("A Markdown file has invalid Memos metadata.")
        }
        let remaining = lines.enumerated().filter { $0.offset != line.offset }.map { String($0.element) }.joined(separator: newline)
        fields["markdown"] = remaining.isEmpty ? body : "---\(newline)\(remaining)---\(newline)\(body)"
        let data = try JSONSerialization.data(withJSONObject: ["memos": [fields]])
        guard let memo = try JSONMemoStore.decodeMemos(data).first else {
            throw StorageError.invalid("A Markdown file has no Memos metadata.")
        }
        return memo
    }

    static func body(of markdown: String) -> String { split(markdown).1 }

    private static func split(_ text: String) -> (String?, String, String) {
        let newline = text.hasPrefix("---\r\n") ? "\r\n" : "\n"
        guard text.hasPrefix("---" + newline),
              let end = text.range(of: newline + "---" + newline, range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else {
            return (nil, text, "\n")
        }
        let start = text.index(text.startIndex, offsetBy: 4)
        return (String(text[start..<text.index(after: end.lowerBound)]), String(text[end.upperBound...]), newline)
    }
}
