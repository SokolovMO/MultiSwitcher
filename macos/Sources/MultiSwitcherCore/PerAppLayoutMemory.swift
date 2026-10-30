import Foundation

/// Stores input-source selections by application bundle identifier in the profile settings.
public enum PerAppLayoutMemory {
    private static let keyPrefix = "com.multiswitcher.perAppLayout.app."

    public static func layouts(in profile: MultiSwitcherProfile) -> [String: String] {
        profile.settings.reduce(into: [:]) { result, entry in
            guard entry.key.hasPrefix(keyPrefix),
                  case .string(let layoutID) = entry.value else { return }
            let bundleID = String(entry.key.dropFirst(keyPrefix.count))
            guard !bundleID.isEmpty, !layoutID.isEmpty else { return }
            result[bundleID] = layoutID
        }
    }

    public static func remember(_ layoutID: String, for bundleID: String,
                                in profile: inout MultiSwitcherProfile) {
        guard !layoutID.isEmpty, !bundleID.isEmpty else { return }
        profile.settings[keyPrefix + bundleID] = .string(layoutID)
    }
}
