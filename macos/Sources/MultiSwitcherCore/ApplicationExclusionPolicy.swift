import Foundation

public enum ApplicationExclusionPolicy {
    /// Entries ending in `*` match a bundle-identifier prefix. Protected apps always remain excluded.
    public static func isExcluded(bundleID: String?, entries: [String], protected: Set<String> = []) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        if protected.contains(bundleID) { return true }
        return entries.contains { entry in
            if entry.hasSuffix("*") {
                return bundleID.hasPrefix(String(entry.dropLast()))
            }
            return entry == bundleID
        }
    }
}
