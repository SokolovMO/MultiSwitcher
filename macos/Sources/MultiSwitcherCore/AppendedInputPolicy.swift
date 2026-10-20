import Foundation

/// Allows a word-boundary replacement to preserve only plain letters typed
/// immediately after the captured boundary. Unknown edits invalidate the snapshot.
public enum AppendedInputPolicy {
    public static func canPreserveTypedSuffix(
        generationDelta: UInt64,
        trackedKeyCount: Int,
        suffix: String,
        maximumKeyCount: Int = 64
    ) -> Bool {
        guard trackedKeyCount >= 0,
              trackedKeyCount <= maximumKeyCount,
              generationDelta == UInt64(trackedKeyCount),
              suffix.count == trackedKeyCount else { return false }
        return suffix.allSatisfy(\.isLetter)
    }
}
