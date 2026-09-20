import Foundation

enum Mark: String, CaseIterable, Sendable {
    case bold, italic, strikethrough, code, link
}

enum Block: Equatable, Sendable {
    case paragraph
    case heading(Int)
    case codeBlock
    case bulletList
    case orderedList
    case taskList
}

struct CaretState: Equatable, Sendable {
    var marks: Set<Mark> = []
    var block: Block = .paragraph
    /// Inside a quote at any depth; `block` is what sits inside it.
    var quoted = false
}

enum FormatCommand: String, Sendable {
    case heading, paragraph, bold, italic, strikethrough, code, codeBlock, quote
    case bulletList, orderedList, taskList, link
}

enum EditorMessage: Sendable {
    case ready
    case changed(String, generation: Int)
    case state(CaretState)
    case openLink(String)
    case error(String)

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "changed":
            guard let markdown = dict["markdown"] as? String, let generation = dict["generation"] as? Int else { return nil }
            self = .changed(markdown, generation: generation)
        case "state":
            let marks = (dict["marks"] as? [String] ?? []).compactMap(Mark.init(rawValue:))
            guard let block = Block(dict["block"]) else { return nil }
            self = .state(CaretState(marks: Set(marks), block: block, quoted: dict["quoted"] as? Bool ?? false))
        case "openLink":
            guard let href = dict["href"] as? String else { return nil }
            self = .openLink(href)
        case "error":
            self = .error(dict["message"] as? String ?? "")
        default:
            return nil
        }
    }
}

extension Block {
    init?(_ value: Any?) {
        guard let dict = value as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "paragraph": self = .paragraph
        case "heading":
            guard let level = dict["level"] as? Int else { return nil }
            self = .heading(level)
        case "codeBlock": self = .codeBlock
        case "bulletList": self = .bulletList
        case "orderedList": self = .orderedList
        case "taskList": self = .taskList
        default: return nil
        }
    }
}
