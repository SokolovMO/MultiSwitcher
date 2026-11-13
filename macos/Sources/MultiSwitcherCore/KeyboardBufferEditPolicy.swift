import Foundation

public enum BackspaceBufferDisposition: Equatable, Sendable {
    /// A plain Backspace can remove one tracked keyboard character.
    case removePreviousCharacter
    /// A modifier can make Backspace remove a word, line, or unknown selection.
    case invalidateTrackedText
}

public enum KeyboardBufferEditPolicy {
    public static func backspaceDisposition(
        command: Bool,
        option: Bool,
        control: Bool
    ) -> BackspaceBufferDisposition {
        command || option || control ? .invalidateTrackedText : .removePreviousCharacter
    }
}
