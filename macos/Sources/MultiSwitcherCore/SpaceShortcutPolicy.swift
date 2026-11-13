import Foundation

public enum SpaceKeyDisposition: Equatable, Sendable {
    case wordBoundary
    case resetForShortcut
    case preserveWordForLayoutSwitch
}

/// Command-Space changes focus to Spotlight; Control-Space changes the input source.
/// Preserve the in-progress word across the latter because each captured key stores its source.
public enum SpaceShortcutPolicy {
    public static func disposition(commandDown: Bool, controlDown: Bool) -> SpaceKeyDisposition {
        if commandDown { return .resetForShortcut }
        if controlDown { return .preserveWordForLayoutSwitch }
        return .wordBoundary
    }
}
