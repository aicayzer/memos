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
        for line in markdown.split(separator: "\n") {
            var text = Substring(line.trimmingCharacters(in: .whitespaces))
            if text.first == "#" {
                text = text.drop(while: { $0 == "#" })
                while text.last == "#" { text = text.dropLast() }
                text = Substring(text.trimmingCharacters(in: .whitespaces))
            }
            if !text.isEmpty { return String(text) }
        }
        return untitled
    }
}
