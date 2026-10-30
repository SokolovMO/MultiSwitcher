import Foundation

public enum ClipboardRestorePolicy {
    /// Restore a saved pasteboard snapshot only when the current generation is still
    /// the generation last written by MultiSwitcher.
    public static func userChangedClipboard(savedChangeCount: Int, ownedChangeCount: Int?,
                                            currentChangeCount: Int) -> Bool {
        if let ownedChangeCount {
            return currentChangeCount != ownedChangeCount
        }
        return currentChangeCount != savedChangeCount
    }

    public static func mayRestore(savedChangeCount: Int, ownedChangeCount: Int?,
                                  currentChangeCount: Int) -> Bool {
        guard let ownedChangeCount,
              !userChangedClipboard(savedChangeCount: savedChangeCount,
                                    ownedChangeCount: ownedChangeCount,
                                    currentChangeCount: currentChangeCount) else { return false }
        return currentChangeCount != savedChangeCount
    }
}
