import Foundation

struct Memo: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var markdown: String
    var pinned: Bool
    let createdAt: Date
    var updatedAt: Date

    var title: String { Memo.title(for: markdown) }

    static let untitled = "Untitled"

    /// The first line as it reads, without its markdown: a quote or a list item titles the memo by its words.
    static func title(for markdown: String) -> String {
        for line in markdown.split(whereSeparator: \.isNewline) {
            let text = plainText(of: line)
            if !text.isEmpty { return text }
        }
        return untitled
    }

    private static func plainText(of line: Substring) -> String {
        var text = Substring(line.trimmingCharacters(in: .whitespaces))
        if text.hasPrefix("```") || text.hasPrefix("~~~") { return "" }
        // Block markers stack, as in `> - [ ] **Call**`.
        while let inner = withoutBlockMarker(text) { text = inner }
        if !text.isEmpty, text.allSatisfy({ "-*_".contains($0) }) { return "" }
        return withoutInlineMarks(String(text)).trimmingCharacters(in: .whitespaces)
    }

    private static func withoutBlockMarker(_ text: Substring) -> Substring? {
        guard let first = text.first else { return nil }
        switch first {
        case ">":
            return Substring(text.dropFirst().trimmingCharacters(in: .whitespaces))
        case "#":
            var inner = text.drop(while: { $0 == "#" })
            // A closing run of marks only counts when a space precedes it, as in CommonMark.
            let closing = inner.reversed().prefix(while: { $0 == "#" }).count
            if closing > 0, inner.dropLast(closing).last == " " { inner = inner.dropLast(closing) }
            return Substring(inner.trimmingCharacters(in: .whitespaces))
        case "-", "*", "+":
            guard text.dropFirst().first == " " else { return nil }
            var inner = Substring(text.dropFirst(2).trimmingCharacters(in: .whitespaces))
            for marker in ["[ ]", "[x]", "[X]"] where inner.hasPrefix(marker) {
                inner = Substring(inner.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
            }
            return inner
        default:
            let digits = text.prefix(while: \.isNumber)
            let rest = text.dropFirst(digits.count)
            guard !digits.isEmpty, digits.count <= 9, rest.first == "." || rest.first == ")", rest.dropFirst().first == " " else {
                return nil
            }
            return Substring(rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
    }

    private static func withoutInlineMarks(_ text: String) -> String {
        var plain = text
        plain = plain.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.1) }
        plain = plain.replacing(/<(https?:\/\/[^>]+)>/) { String($0.1) }
        plain = plain.replacing(/`([^`]+)`/) { String($0.1) }
        plain = plain.replacing(/(\*\*|__|~~)(.+?)\1/) { String($0.2) }
        plain = plain.replacing(/\*([^*\s][^*]*?)\*/) { String($0.1) }
        plain = plain.replacing(/\b_([^_\s][^_]*?)_\b/) { String($0.1) }
        return plain
    }
}
