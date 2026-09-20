import SwiftUI

struct FormatBar: View {
    let editor: EditorController
    let hide: () -> Void

    private var caret: CaretState { editor.caret }

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(1...3, id: \.self) { level in
                    Button("Heading \(level)") { editor.format(.heading, argument: String(level)) }
                }
                Button("Paragraph") { editor.format(.paragraph) }
            } label: {
                Image(systemName: headingSymbol)
            }
            .menuIndicator(.visible)
            .tint(caret.block.isHeading ? .accentColor : .secondary)

            Menu {
                Button("Bold") { editor.format(.bold) }
                Button("Italic") { editor.format(.italic) }
                Button("Strikethrough") { editor.format(.strikethrough) }
            } label: {
                Image(systemName: "italic")
            }
            .menuIndicator(.visible)
            .tint(caret.marks.isDisjoint(with: [.bold, .italic, .strikethrough]) ? .secondary : .accentColor)

            button("link", active: caret.marks.contains(.link)) { editor.format(.link) }
            button("chevron.left.forwardslash.chevron.right", active: caret.marks.contains(.code)) { editor.format(.code) }

            divider

            button("curlybraces", active: caret.block == .codeBlock) { editor.format(.codeBlock) }
            button("text.quote", active: caret.block == .quote) { editor.format(.quote) }

            divider

            Menu {
                Button("Bulleted List") { editor.format(.bulletList) }
                Button("Numbered List") { editor.format(.orderedList) }
                Button("Task List") { editor.format(.taskList) }
            } label: {
                Image(systemName: listSymbol)
            }
            .menuIndicator(.visible)
            .tint(caret.block.isList ? .accentColor : .secondary)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.borderless)
        .imageScale(.medium)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    private var divider: some View {
        Divider().frame(height: 16).padding(.horizontal, 6)
    }

    private func button(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 24)
        }
        .tint(active ? .accentColor : .secondary)
    }

    private var headingSymbol: String {
        if case .heading(let level) = caret.block, (1...3).contains(level) { return "h\(level).square" }
        return "textformat.size"
    }

    private var listSymbol: String {
        switch caret.block {
        case .orderedList: "list.number"
        case .taskList: "checklist"
        default: "list.bullet"
        }
    }
}

extension Block {
    var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }

    var isList: Bool {
        switch self {
        case .bulletList, .orderedList, .taskList: true
        default: false
        }
    }
}
