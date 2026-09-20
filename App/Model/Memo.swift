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
            let text = plainText(of: line.prefix(300))
            if !text.isEmpty { return text }
        }
        return untitled
    }

    private static func plainText(of line: Substring) -> String {
        var text = Substring(line.trimmingCharacters(in: .whitespaces))
        if text.hasPrefix("```") || text.hasPrefix("~~~") { return "" }
        // Quotes and lists nest, as in `> - [ ] **Call**`; a heading's text is then plain.
        while let inner = withoutContainerMarker(text) { text = inner }
        if text.first == "#" { text = withoutHeadingMarks(text) }
        if !text.isEmpty, text.allSatisfy({ "-*_".contains($0) }) { return "" }
        return withoutInlineMarks(String(text)).trimmingCharacters(in: .whitespaces)
    }

    private static func withoutContainerMarker(_ text: Substring) -> Substring? {
        guard let first = text.first else { return nil }
        switch first {
        case ">":
            return Substring(text.dropFirst().trimmingCharacters(in: .whitespaces))
        case "-", "*", "+":
            guard text.dropFirst().first == " " else { return nil }
            var inner = Substring(text.dropFirst(2).trimmingCharacters(in: .whitespaces))
            for marker in ["[ ]", "[x]", "[X]"] where inner.hasPrefix(marker) {
                inner = Substring(inner.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
            }
            return inner
        default:
            let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
            let rest = text.dropFirst(digits.count)
            guard !digits.isEmpty, digits.count <= 9, rest.first == "." || rest.first == ")", rest.dropFirst().first == " " else {
                return nil
            }
            return Substring(rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
    }

    private static func withoutHeadingMarks(_ text: Substring) -> Substring {
        var inner = text.drop(while: { $0 == "#" })
        // A closing run of marks only counts when a space precedes it, as in CommonMark.
        let closing = inner.reversed().prefix(while: { $0 == "#" }).count
        if closing > 0, inner.dropLast(closing).last == " " { inner = inner.dropLast(closing) }
        return Substring(inner.trimmingCharacters(in: .whitespaces))
    }

    private static func withoutInlineMarks(_ text: String) -> String {
        // Escaped punctuation and code span contents are literal; they sit out the stripping as private-use characters.
        var plain = text.replacing(/\\([!-\/:-@\[-`{-~])/) { shielded($0.1) }
        plain = plain.replacing(/`([^`]+)`/) { shielded($0.1) }
        plain = plain.replacing(/!?\[([^\[\]]*)\]\(([^()\s]*)\)/) { String($0.1) }
        plain = plain.replacing(/<(https?:\/\/[^<>\s]+)>/) { String($0.1) }
        plain = plain.replacing(/(\*\*|__|~~)([^*_~]+)\1/) { String($0.2) }
        plain = plain.replacing(/\*([^*\s][^*]*)\*/) { String($0.1) }
        plain = plain.replacing(/\b_([^_\s][^_]*)_\b/) { String($0.1) }
        return String(String.UnicodeScalarView(plain.unicodeScalars.map(unshielded)))
    }

    private static func shielded(_ text: Substring) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            scalar.value >= 0x21 && scalar.value <= 0x7E ? Unicode.Scalar(scalar.value + 0xE000)! : scalar
        }))
    }

    private static func unshielded(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        scalar.value >= 0xE021 && scalar.value <= 0xE07E ? Unicode.Scalar(scalar.value - 0xE000)! : scalar
    }
}
