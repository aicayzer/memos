import CoreGraphics
import Foundation

enum EditorCountUnit: String {
    case characters, words
}

struct EditorCounts: Equatable, Sendable {
    let characters: Int
    let words: Int

    func label(for unit: EditorCountUnit) -> String {
        let value = unit == .characters ? characters : words
        let name = unit == .characters ? (value == 1 ? "character" : "characters") : (value == 1 ? "word" : "words")
        return "\(value.formatted()) \(name)"
    }
}

enum Mark: String, Sendable {
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
    var sourceMode = false
    var commands: [String: Bool] = [:]
    var formats: [String: Bool] = [:]
    var tables: [String: Bool] = [:]
}

enum FormatCommand: String, Sendable {
    case heading1, heading2, heading3, paragraph, bold, italic, strikethrough, code, codeBlock, quote
    case bulletList, orderedList, taskList, link
}

enum EditorMessage: Sendable {
    case ready
    case changed(String, generation: Int, sequence: Int? = nil)
    case commandState(CaretState, documentID: String, generation: Int)
    case textCounts(EditorCounts, documentID: String, generation: Int)
    case openLink(String)
    case imageMenu(reference: String, at: CGPoint)
    case copy(String)
    case warning(String)
    case error(String)

    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready":
            self = .ready
        case "changed":
            guard let markdown = dict["markdown"] as? String, let generation = dict["generation"] as? Int else { return nil }
            self = .changed(markdown, generation: generation, sequence: dict["sequence"] as? Int)
        case "commandState":
            guard let documentID = dict["documentId"] as? String, let generation = dict["generation"] as? Int,
                  let commands = dict["commands"] as? [String: Any], let caret = dict["caret"] as? [String: Any],
                  let block = Block(caret["block"]) else { return nil }
            var state = CaretState(marks: Set((caret["marks"] as? [String] ?? []).compactMap(Mark.init(rawValue:))), block: block, quoted: caret["quoted"] as? Bool ?? false)
            state.sourceMode = dict["mode"] as? String == "source"
            state.commands = commands.compactMapValues { $0 as? Bool }
            state.formats = commands["format"] as? [String: Bool] ?? [:]
            state.tables = commands["table"] as? [String: Bool] ?? [:]
            self = .commandState(state, documentID: documentID, generation: generation)
        case "textCounts":
            guard let documentID = dict["documentId"] as? String,
                  let generation = dict["generation"] as? Int,
                  let characters = dict["characters"] as? Int, characters >= 0,
                  let words = dict["words"] as? Int, words >= 0 else { return nil }
            self = .textCounts(EditorCounts(characters: characters, words: words), documentID: documentID, generation: generation)
        case "openLink":
            guard let href = dict["href"] as? String else { return nil }
            self = .openLink(href)
        case "imageMenu":
            guard let reference = dict["reference"] as? String,
                  let x = (dict["x"] as? NSNumber)?.doubleValue, let y = (dict["y"] as? NSNumber)?.doubleValue,
                  x.isFinite, y.isFinite else { return nil }
            self = .imageMenu(reference: reference, at: CGPoint(x: x, y: y))
        case "copy":
            guard let text = dict["text"] as? String else { return nil }
            self = .copy(text)
        case "editorWarning":
            self = .warning(dict["message"] as? String ?? "")
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
