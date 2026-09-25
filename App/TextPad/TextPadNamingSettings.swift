import AppKit
import SwiftUI

struct TextPadNamingSettings: View {
    @Bindable var files: TextPad

    var body: some View {
        HStack {
            Text("File name")
            Spacer()
            TextPadNameField(parts: $files.nameParts)
                .frame(width: 310, height: 26)
        }
    }
}

struct TextPadNameField: NSViewRepresentable {
    @Binding var parts: [TextPadNamePart]
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> FilenameInput {
        let input = FilenameInput()
        input.changed = { parts = $0 }
        input.setParts(parts)
        return input
    }

    static func dismantleNSView(_ input: FilenameInput, coordinator: ()) {
        input.changed = { _ in }
        input.field.objectValue = []
        input.field.delegate = nil
    }

    func updateNSView(_ input: FilenameInput, context: Context) {
        input.changed = { parts = $0 }
        input.setParts(parts)
        input.field.isEnabled = isEnabled
        input.add.isEnabled = isEnabled
    }
}

final class FilenameInput: NSView, NSTokenFieldDelegate {
    private final class Token: NSObject {
        let value: TextPadNameToken
        init(_ value: TextPadNameToken) { self.value = value }
    }

    let field = NSTokenField()
    let add = NSPopUpButton(frame: .zero, pullsDown: true)
    var changed: ([TextPadNamePart]) -> Void = { _ in }
    private var displayed: [TextPadNamePart] = []
    private var synchronizing = false
    private static let pasteboardType = NSPasteboard.PasteboardType("memos.filename-parts")

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.delegate = self
        field.font = .systemFont(ofSize: 12)
        field.tokenizingCharacterSet = CharacterSet()
        field.completionDelay = .greatestFiniteMagnitude
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("File name")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        add.refusesFirstResponder = true
        add.isBordered = false
        add.imagePosition = .imageOnly
        add.setAccessibilityLabel("Insert filename variable")
        let menu = NSMenu()
        let label = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        label.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Insert filename variable")
        menu.addItem(label)
        for (index, token) in TextPadNameToken.allCases.enumerated() {
            let item = NSMenuItem(title: token.title, action: #selector(insertVariable(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        add.menu = menu
        for view in [field, add] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: add.leadingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            add.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            add.widthAnchor.constraint(equalToConstant: 24),
            add.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 5
    }

    func setParts(_ parts: [TextPadNamePart]) {
        guard parts != displayed else { return }
        displayed = parts
        field.objectValue = objects(parts)
    }

    private func objects(_ parts: [TextPadNamePart]) -> [Any] {
        parts.map { part in
            switch part {
            case let .literal(text): text as NSString
            case let .token(token): Token(token)
            }
        }
    }

    private func parts(_ objects: [Any]) -> [TextPadNamePart] {
        objects.compactMap { object in
            if let token = object as? Token { return .token(token.value) }
            if let text = object as? String, !text.isEmpty { return .literal(text) }
            return nil
        }
    }

    private func sync() {
        guard !synchronizing else { return }
        synchronizing = true
        let previous = displayed
        defer { synchronizing = false }
        if let editor = field.currentEditor() as? NSTextView {
            var result: [TextPadNamePart] = []
            let text = editor.attributedString()
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                let cell = (value as? NSTextAttachment)?.attachmentCell as? NSCell
                if let token = cell?.representedObject as? Token {
                    result.append(.token(token.value))
                } else {
                    let literal = (text.string as NSString).substring(with: range)
                    if case let .literal(previous) = result.last {
                        result[result.count - 1] = .literal(previous + literal)
                    } else if !literal.isEmpty {
                        result.append(.literal(literal))
                    }
                }
            }
            displayed = result
        } else {
            displayed = parts(field.objectValue as? [Any] ?? [])
        }
        if displayed != previous { changed(displayed) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard window != nil else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(textStorageChanged),
                                               name: NSTextStorage.didProcessEditingNotification, object: nil)
    }

    // Read the live editor: token-field objectValue omits text that has not been tokenized yet.
    @objc private func textStorageChanged(_ notification: Notification) {
        guard let editor = field.currentEditor() as? NSTextView,
              notification.object as? NSTextStorage === editor.textStorage else { return }
        scheduleSync()
    }

    private func scheduleSync() {
        DispatchQueue.main.async { [weak self] in
            guard let self, field.currentEditor() != nil else { return }
            sync()
        }
    }

    func controlTextDidChange(_ notification: Notification) { scheduleSync() }
    func controlTextDidEndEditing(_ notification: Notification) { sync() }

    @objc private func insertVariable(_ sender: NSMenuItem) {
        insert(TextPadNameToken.allCases[sender.tag])
    }

    func insert(_ token: TextPadNameToken) {
        guard let window, field.isEnabled else { return }
        let editor = field.currentEditor() as? NSTextView
        let selection = editor?.selectedRange() ?? NSRange(location: displayed.reduce(0) { $0 + Self.length($1) }, length: 0)
        sync()
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            let source = NSTokenField()
            source.delegate = self
            source.objectValue = [Token(token)]
            let value = source.attributedStringValue
            editor.breakUndoCoalescing()
            editor.insertText(value, replacementRange: selection)
            editor.breakUndoCoalescing()
            sync()
            source.objectValue = []
            source.delegate = nil
        }
    }

    static func length(_ part: TextPadNamePart) -> Int {
        switch part {
        case let .literal(text): (text as NSString).length
        case .token: 1
        }
    }

    func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject object: Any) -> String? {
        (object as? Token)?.value.title ?? object as? String
    }

    func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject object: Any) -> String? {
        object is Token ? nil : object as? String
    }

    func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
        editingString as NSString
    }

    func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject object: Any) -> NSTokenField.TokenStyle {
        object is Token ? .rounded : .none
    }

    func tokenField(_ tokenField: NSTokenField, writeRepresentedObjects objects: [Any], to pasteboard: NSPasteboard) -> Bool {
        let parts = parts(objects)
        guard let data = try? JSONEncoder().encode(parts) else { return false }
        pasteboard.declareTypes([Self.pasteboardType, .string], owner: nil)
        pasteboard.setData(data, forType: Self.pasteboardType)
        pasteboard.setString(objects.compactMap { self.tokenField(tokenField, displayStringForRepresentedObject: $0) }.joined(), forType: .string)
        return true
    }

    func tokenField(_ tokenField: NSTokenField, readFrom pasteboard: NSPasteboard) -> [Any]? {
        if let data = pasteboard.data(forType: Self.pasteboardType),
           let parts = try? JSONDecoder().decode([TextPadNamePart].self, from: data) { return objects(parts) }
        return pasteboard.string(forType: .string).map { [$0 as NSString] }
    }
}
