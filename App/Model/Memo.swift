import Foundation

struct Memo: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var markdown: String
    var pinned: Bool
    let createdAt: Date
    var updatedAt: Date

    var title: String { Memo.title(for: markdown) }

    static let untitled = "Untitled"

    static func title(for markdown: String) -> String {
        for line in markdown.split(whereSeparator: \.isNewline) {
            var text = Substring(line.trimmingCharacters(in: .whitespacesAndNewlines))
            if text.first == "#" {
                text = text.drop(while: { $0 == "#" })
                // A closing run of marks only counts when a space precedes it, as in CommonMark.
                let closing = text.reversed().prefix(while: { $0 == "#" }).count
                if closing > 0, text.dropLast(closing).last == " " { text = text.dropLast(closing) }
                text = Substring(text.trimmingCharacters(in: .whitespaces))
            }
            if !text.isEmpty { return String(text) }
        }
        return untitled
    }
}
