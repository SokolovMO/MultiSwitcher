import Foundation

public enum PauseStatePolicy {
    public static func hasExpiredDeadline(_ deadline: Date?, now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        return deadline <= now
    }
}
