import CryptoKit
import Foundation

public enum ProfileStoreError: LocalizedError {
    case unsupportedSchema(Int)
    case unreadableProfile
    case noPreviousProfile
    case invalidPreviousProfile
    case invalidSnapshotName

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "The MultiSwitcher profile schema \(version) is newer than this app supports."
        case .unreadableProfile:
            return "The saved MultiSwitcher profile could not be read. The original file was preserved."
        case .noPreviousProfile:
            return "No previous MultiSwitcher profile backup is available."
        case .invalidPreviousProfile:
            return "The previous MultiSwitcher profile backup is invalid. The original file was preserved."
        case .invalidSnapshotName:
            return "A safe name for the Punto backup could not be created."
        }
    }
}

/// Local versioned storage with atomic profile replacement and a previous-generation copy.
public final class ProfileStore: @unchecked Sendable {
    public static let shared: ProfileStore = {
        if let root = MultiAuditEnvironment.root {
            return ProfileStore(rootURL: root.appendingPathComponent("profile", isDirectory: true))
        }
        return ProfileStore()
    }()

    public let rootURL: URL
    public let profileURL: URL
    public let backupsURL: URL

    private let lock = NSRecursiveLock()
    private var cached: MultiSwitcherProfile
    private var loadFailure: Error?
    private var generation: UInt64 = 0
    private var ruleGeneration: UInt64 = 0

    public init(rootURL: URL? = nil) {
        let base = rootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MultiSwitcher", isDirectory: true)
        self.rootURL = base
        self.profileURL = base.appendingPathComponent("profile.json")
        self.backupsURL = base.appendingPathComponent("Backups", isDirectory: true)

        if FileManager.default.fileExists(atPath: profileURL.path) {
            do {
                let data = try Data(contentsOf: profileURL)
                var decoded = try JSONDecoder.multiSwitcher.decode(MultiSwitcherProfile.self, from: data)
                guard decoded.schemaVersion <= MultiSwitcherProfile.currentSchemaVersion else {
                    throw ProfileStoreError.unsupportedSchema(decoded.schemaVersion)
                }
                decoded.migrateToCurrentSchema()
                self.cached = decoded
            } catch {
                self.cached = MultiSwitcherProfile()
                self.loadFailure = error
            }
        } else {
            self.cached = MultiSwitcherProfile()
        }
    }

    public var current: MultiSwitcherProfile {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Monotonic in-process revision for read-mostly consumers that cache derived data.
    public var currentGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// Revision for data that affects compiled conversion rules. Changes to unrelated
    /// preferences and learning evidence do not force a rebuild on the keyboard path.
    public var currentRuleGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return ruleGeneration
    }

    /// A coherent profile/revision pair for rebuilding derived snapshots after a write.
    public func versionedSnapshot() -> (generation: UInt64, profile: MultiSwitcherProfile) {
        lock.lock()
        defer { lock.unlock() }
        return (generation, cached)
    }

    /// Coherent rule-specific revision/profile pair for derived rule snapshots.
    public func versionedRuleSnapshot() -> (generation: UInt64, profile: MultiSwitcherProfile) {
        lock.lock()
        defer { lock.unlock() }
        return (ruleGeneration, cached)
    }

    private func ruleInputsChanged(from old: MultiSwitcherProfile, to new: MultiSwitcherProfile) -> Bool {
        old.rules != new.rules
            || old.settings[ProfileRuleMaintenance.deniedWordsSettingKey]
                != new.settings[ProfileRuleMaintenance.deniedWordsSettingKey]
            || old.settings[ProfileRuleMaintenance.alwaysConvertWordsSettingKey]
                != new.settings[ProfileRuleMaintenance.alwaysConvertWordsSettingKey]
    }

    private func advanceRuleGenerationIfNeeded(from old: MultiSwitcherProfile, to new: MultiSwitcherProfile) {
        if ruleInputsChanged(from: old, to: new) {
            ruleGeneration &+= 1
        }
    }

    /// The app stays read-only when the primary profile cannot be decoded. Expose that
    /// state so Settings can explain the problem instead of silently showing defaults.
    public var isInRecoveryMode: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadFailure != nil
    }

    public var canRestorePreviousProfile: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadFailure != nil
            && FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("profile.json.previous").path)
    }

    /// Restores only a decodable, supported previous generation. The damaged primary
    /// is copied to a timestamped recovery file before the previous generation replaces it.
    @discardableResult
    public func restorePreviousProfile() throws -> MultiSwitcherProfile {
        lock.lock()
        defer { lock.unlock() }
        guard loadFailure != nil else { return cached }

        let previousURL = rootURL.appendingPathComponent("profile.json.previous")
        guard FileManager.default.fileExists(atPath: previousURL.path) else {
            throw ProfileStoreError.noPreviousProfile
        }
        let data = try Data(contentsOf: previousURL)
        var decoded: MultiSwitcherProfile
        do {
            decoded = try JSONDecoder.multiSwitcher.decode(MultiSwitcherProfile.self, from: data)
            guard decoded.schemaVersion <= MultiSwitcherProfile.currentSchemaVersion else {
                throw ProfileStoreError.unsupportedSchema(decoded.schemaVersion)
            }
            decoded.migrateToCurrentSchema()
        } catch {
            throw ProfileStoreError.invalidPreviousProfile
        }

        let manager = FileManager.default
        try manager.createDirectory(at: backupsURL, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        if manager.fileExists(atPath: profileURL.path) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let recoveryURL = backupsURL.appendingPathComponent("profile-unreadable-\(stamp).json")
            try manager.copyItem(at: profileURL, to: recoveryURL)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
        }
        let restoredData = try JSONEncoder.multiSwitcher.encode(decoded)
        try restoredData.write(to: profileURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profileURL.path)
        advanceRuleGenerationIfNeeded(from: cached, to: decoded)
        cached = decoded
        loadFailure = nil
        generation &+= 1
        return decoded
    }

    @discardableResult
    public func update(_ change: (inout MultiSwitcherProfile) throws -> Void) throws -> MultiSwitcherProfile {
        lock.lock()
        defer { lock.unlock() }
        if loadFailure != nil { throw ProfileStoreError.unreadableProfile }
        var next = cached
        next.migrateToCurrentSchema()
        try change(&next)
        next.schemaVersion = MultiSwitcherProfile.currentSchemaVersion
        try writeAtomically(next)
        advanceRuleGenerationIfNeeded(from: cached, to: next)
        cached = next
        generation &+= 1
        return next
    }

    public func reload() throws -> MultiSwitcherProfile {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: profileURL.path) else {
            let empty = MultiSwitcherProfile()
            advanceRuleGenerationIfNeeded(from: cached, to: empty)
            cached = empty
            loadFailure = nil
            generation &+= 1
            return cached
        }
        do {
            let data = try Data(contentsOf: profileURL)
            var decoded = try JSONDecoder.multiSwitcher.decode(MultiSwitcherProfile.self, from: data)
            guard decoded.schemaVersion <= MultiSwitcherProfile.currentSchemaVersion else {
                throw ProfileStoreError.unsupportedSchema(decoded.schemaVersion)
            }
            decoded.migrateToCurrentSchema()
            advanceRuleGenerationIfNeeded(from: cached, to: decoded)
            cached = decoded
            loadFailure = nil
            generation &+= 1
            return decoded
        } catch {
            loadFailure = error
            throw error
        }
    }

    @discardableResult
    public func importPuntoProfile(from sourceURL: URL) throws -> PuntoAppliedImportReport {
        let snapshot = try createPuntoSnapshot(sourceURL: sourceURL)
        let parsed = try PuntoProfileImporter.read(from: snapshot.url)
        let snapshotName = snapshot.url.deletingLastPathComponent().lastPathComponent
            + "/" + snapshot.url.lastPathComponent
        var applied: PuntoAppliedImportReport?
        try update { profile in
            applied = PuntoProfileMigration.apply(
                parsed,
                sourceSnapshotName: snapshotName,
                sourceSHA256: snapshot.sha256,
                to: &profile
            )
        }
        guard let applied else { throw ProfileStoreError.unreadableProfile }
        return applied
    }

    /// Copies the original settings file before parsing/import. The original is never modified.
    public func createPuntoSnapshot(sourceURL: URL) throws -> (url: URL, sha256: String) {
        let manager = FileManager.default
        try manager.createDirectory(at: backupsURL, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let sourceData = try Data(contentsOf: sourceURL)
        let digest = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
        let filename = sourceURL.lastPathComponent
        let safeName = filename.replacingOccurrences(of: "/", with: "_")
        guard !safeName.isEmpty else { throw ProfileStoreError.invalidSnapshotName }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = backupsURL.appendingPathComponent("Punto-\(stamp)", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        let snapshotURL = folder.appendingPathComponent(safeName)
        try sourceData.write(to: snapshotURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
        let manifest: [String: String] = [
            "capturedAt": formatter.string(from: Date()),
            "sourceName": filename,
            "snapshotName": safeName,
            "sha256": digest,
            "bytes": String(sourceData.count)
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        let manifestURL = folder.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        return (snapshotURL, digest)
    }

    /// Captures the exact on-disk profile generation before a potentially disruptive
    /// operation such as an app update. The snapshot is immutable and private to the
    /// current user; a malformed profile is copied as-is for recovery instead of being
    /// replaced with defaults.
    @discardableResult
    public func createBackupSnapshot(label: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        let safeLabel = label.lowercased().replacingOccurrences(
            of: "[^a-z0-9-]", with: "-", options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !safeLabel.isEmpty, safeLabel.count <= 48 else {
            throw ProfileStoreError.invalidSnapshotName
        }

        let manager = FileManager.default
        try manager.createDirectory(at: backupsURL, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = backupsURL.appendingPathComponent("Snapshot-\(safeLabel)-\(stamp)-\(UUID().uuidString.prefix(8))",
                                                       isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])

        let profileData: Data
        if manager.fileExists(atPath: profileURL.path) {
            profileData = try Data(contentsOf: profileURL)
        } else {
            profileData = try JSONEncoder.multiSwitcher.encode(cached)
        }
        let snapshotURL = folder.appendingPathComponent("profile.json")
        try profileData.write(to: snapshotURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)

        let previousURL = rootURL.appendingPathComponent("profile.json.previous")
        let includesPrevious = manager.fileExists(atPath: previousURL.path)
        if includesPrevious {
            let copy = folder.appendingPathComponent("profile.json.previous")
            try manager.copyItem(at: previousURL, to: copy)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
        }

        let digest = SHA256.hash(data: profileData).map { String(format: "%02x", $0) }.joined()
        let manifest: [String: Any] = [
            "snapshotVersion": 1,
            "label": safeLabel,
            "createdAt": formatter.string(from: Date()),
            "profileSHA256": digest,
            "profileBytes": profileData.count,
            "includesPreviousProfile": includesPrevious
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        let manifestURL = folder.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        return folder
    }

    private func writeAtomically(_ profile: MultiSwitcherProfile) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        if manager.fileExists(atPath: profileURL.path) {
            let previous = try Data(contentsOf: profileURL)
            try previous.write(to: rootURL.appendingPathComponent("profile.json.previous"), options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600],
                                      ofItemAtPath: rootURL.appendingPathComponent("profile.json.previous").path)
        }
        let data = try JSONEncoder.multiSwitcher.encode(profile)
        try data.write(to: profileURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profileURL.path)
    }
}

private extension JSONEncoder {
    static var multiSwitcher: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var multiSwitcher: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
