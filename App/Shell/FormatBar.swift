import SwiftUI

struct FormatBar: View {
    let editor: EditorController

    @State private var linkPopover = false
    @State private var linkURL = ""

    private var caret: CaretState { editor.caret }

    var body: some View {
        HStack(spacing: 2) {
            menu("Heading", active: caret.block.isHeading) {
                ForEach(1...3, id: \.self) { level in
                    Toggle("Heading \(level)", isOn: toggle(caret.block == .heading(level)) {
                        editor.format(.heading, argument: String(level))
                    })
                }
            } label: {
                Image(nsImage: Self.headingGlyph(active: caret.block.isHeading))
            }

            menu("Text Style", active: !caret.marks.isDisjoint(with: [.bold, .italic, .strikethrough])) {
                Toggle("Bold", isOn: toggle(caret.marks.contains(.bold)) { editor.format(.bold) })
                Toggle("Italic", isOn: toggle(caret.marks.contains(.italic)) { editor.format(.italic) })
                Toggle("Strikethrough", isOn: toggle(caret.marks.contains(.strikethrough)) { editor.format(.strikethrough) })
            } label: {
                Image(nsImage: Self.styleGlyph(active: !caret.marks.isDisjoint(with: [.bold, .italic, .strikethrough])))
            }

            button("link", "Link", size: Chrome.iconSize - 1, active: caret.marks.contains(.link)) {
                if caret.marks.contains(.link) {
                    editor.format(.link)
                } else {
                    linkURL = ""
                    linkPopover = true
                }
            }
            .popover(isPresented: $linkPopover, arrowEdge: .top) {
                TextField("https://", text: $linkURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .padding(12)
                    .onSubmit {
                        linkPopover = false
                        let url = linkURL.trimmingCharacters(in: .whitespaces)
                        if !url.isEmpty { editor.format(.link, argument: url) }
                    }
            }
            button("chevron.left.forwardslash.chevron.right", "Inline Code", size: Chrome.iconSize - 2, active: caret.marks.contains(.code)) {
                editor.format(.code)
            }

            divider

            button("curlybraces", "Code Block", active: caret.block == .codeBlock) { editor.format(.codeBlock) }
            button("text.quote", "Quote", active: caret.quoted) { editor.format(.quote) }

            divider

            menu("List", active: caret.block.isList) {
                Toggle("Bulleted List", isOn: toggle(caret.block == .bulletList) { editor.format(.bulletList) })
                Toggle("Numbered List", isOn: toggle(caret.block == .orderedList) { editor.format(.orderedList) })
                Toggle("Task List", isOn: toggle(caret.block == .taskList) { editor.format(.taskList) })
            } label: {
                Image(systemName: listSymbol).font(.system(size: Chrome.iconSize, weight: .medium))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(height: Chrome.barHeight)
        .glassEffect(.regular, in: .capsule)
    }

    private var divider: some View {
        Divider().frame(height: 12).padding(.horizontal, 4)
    }

    // A menu item's check mark shows the state; choosing it runs the command either way.
    private func toggle(_ on: Bool, _ action: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { on }, set: { _ in action() })
    }

    // A borderless menu draws a text label, and a template image, in the label color whatever the tint,
    // so the glyph is drawn in the label color it should have. The drawing handler runs at draw time,
    // so the dynamic colors follow the appearance.
    private static let headingFont = NSFont.systemFont(ofSize: Chrome.iconSize + 1, weight: .semibold).withDesign(.rounded)
    private static let styleFont = NSFont.systemFont(ofSize: Chrome.iconSize, weight: .medium).withDesign(.serif)
    private static let headingGlyphs = (on: glyph("H", headingFont, .labelColor), off: glyph("H", headingFont, .secondaryLabelColor))
    private static let styleGlyphs = (on: glyph("I", styleFont, .labelColor), off: glyph("I", styleFont, .secondaryLabelColor))

    private static func headingGlyph(active: Bool) -> NSImage { active ? headingGlyphs.on : headingGlyphs.off }
    private static func styleGlyph(active: Bool) -> NSImage { active ? styleGlyphs.on : styleGlyphs.off }

    private static func glyph(_ text: String, _ font: NSFont, _ color: NSColor) -> NSImage {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = attributed.size()
        return NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { rect in
            attributed.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: 0))
            return true
        }
    }

    // The borderless menu button reads its label as icon plus title, so the label stays a single glyph.
    private func menu<Items: View, Glyph: View>(
        _ label: String, active: Bool, @ViewBuilder _ items: () -> Items, @ViewBuilder label glyph: () -> Glyph
    ) -> some View {
        let menu = Menu(content: items) { glyph().frame(height: 26) }
        return HoverHighlight {
            menu
                .tint(active ? .primary : .secondary)
                .accessibilityLabel(label)
        }
    }

    private func button(
        _ symbol: String, _ label: String, size: CGFloat = Chrome.iconSize, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HoverHighlight {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .medium))
                    .frame(width: 28, height: 26)
            }
        }
        .tint(active ? .primary : .secondary)
        .accessibilityLabel(label)
        .help(label)
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

private extension NSFont {
    func withDesign(_ design: NSFontDescriptor.SystemDesign) -> NSFont {
        fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? self
    }
}
