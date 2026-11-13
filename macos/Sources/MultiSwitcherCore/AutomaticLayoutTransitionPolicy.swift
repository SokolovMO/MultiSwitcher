import Foundation

/// Pure guard for an automatic input-source change that completes asynchronously.
/// The caller selects a source only when the exact captured source is still active.
public enum AutomaticLayoutTransitionPolicy {
    public enum Decision: Equatable, Sendable {
        case keep
        case alreadyAtTarget
        case sourceUnavailable
        case preserveUserChoice
        case select(String)
    }

    public static func decide(
        sourceLayoutID: String?,
        currentLayoutID: String,
        targetLayoutID: String?
    ) -> Decision {
        guard let targetLayoutID, !targetLayoutID.isEmpty else { return .keep }
        if currentLayoutID == targetLayoutID { return .alreadyAtTarget }
        guard let sourceLayoutID, !sourceLayoutID.isEmpty else { return .sourceUnavailable }
        guard currentLayoutID == sourceLayoutID else { return .preserveUserChoice }
        return .select(targetLayoutID)
    }
}
