import Foundation

public enum UpdateChannel: String, Sendable, CaseIterable {
    case stable
    case beta
}

public struct PublishedRelease: Equatable, Sendable {
    public let tag: String
    public let version: String
    public let buildNumber: String
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let publishedAt: String

    public init(tag: String, version: String, buildNumber: String, isDraft: Bool,
                isPrerelease: Bool, publishedAt: String) {
        self.tag = tag
        self.version = version
        self.buildNumber = buildNumber
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.publishedAt = publishedAt
    }
}

public enum UpdateChannelPolicy {
    public static func isValidTag(_ tag: String, channel: UpdateChannel) -> Bool {
        let prefix = channel == .beta ? "beta-v" : "v"
        guard tag.hasPrefix(prefix) else { return false }
        let versionAndBuild = tag.dropFirst(prefix.count)
        guard versionAndBuild.range(
            of: "^[0-9]+(?:\\.[0-9]+){1,3}-build[0-9]+(?:\\.[0-9]+)*$",
            options: .regularExpression
        ) != nil,
              let marker = versionAndBuild.range(of: "-build") else { return false }

        let versionParts = versionAndBuild[..<marker.lowerBound].split(separator: ".")
        let buildParts = versionAndBuild[marker.upperBound...].split(separator: ".")
        // Bound numeric components before converting to Int, so malformed public
        // release metadata cannot overflow version comparison.
        return (versionParts + buildParts).allSatisfy { $0.count <= 9 && Int($0) != nil }
    }

    /// Beta users receive published beta builds and newer stable builds. Stable users
    /// never receive prereleases. Draft releases are never install candidates.
    public static func select(_ releases: [PublishedRelease], channel: UpdateChannel) -> PublishedRelease? {
        let eligible = releases.filter { release in
            guard !release.isDraft else { return false }
            switch channel {
            case .stable:
                return !release.isPrerelease && isValidTag(release.tag, channel: .stable)
            case .beta:
                return isValidTag(release.tag, channel: .beta) == release.isPrerelease
                    && (release.isPrerelease || isValidTag(release.tag, channel: .stable))
            }
        }

        return eligible.max { lhs, rhs in
            let versionOrder = compareNumericComponents(lhs.version, rhs.version)
            if versionOrder != .orderedSame { return versionOrder == .orderedAscending }
            let buildOrder = compareNumericComponents(lhs.buildNumber, rhs.buildNumber)
            if buildOrder != .orderedSame { return buildOrder == .orderedAscending }
            return lhs.publishedAt < rhs.publishedAt
        }
    }

    private static func compareNumericComponents(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        guard left.count == lhs.split(separator: ".").count,
              right.count == rhs.split(separator: ".").count else { return .orderedSame }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
