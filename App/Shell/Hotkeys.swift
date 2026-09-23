import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleWindow = Self("toggleWindow", initial: .init(.b, modifiers: [.option]))
    /// M for memo: near the other one without being a slip of the finger from it.
    static let newMemo = Self("newMemo", initial: .init(.m, modifiers: [.control, .option]))
}
