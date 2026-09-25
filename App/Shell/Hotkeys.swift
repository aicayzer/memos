import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    #if DEBUG
    private static let devModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    #else
    private static let devModifiers: NSEvent.ModifierFlags = []
    #endif

    static let toggleWindow = Self("toggleWindow", initial: .init(.b, modifiers: devModifiers.union(.option)))
    /// M for memo: near the other one without being a slip of the finger from it.
    static let newMemo = Self("newMemo", initial: .init(.m, modifiers: devModifiers.union([.control, .option])))
    static let textPad = Self("textPad", initial: .init(.b, modifiers: devModifiers.union([.option, .shift])))
}
