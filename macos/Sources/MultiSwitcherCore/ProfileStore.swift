import CryptoKit
import Foundation

public enum ProfileStoreError: LocalizedError {
    case unsupportedSchema(Int)
    case unreadableProfile
    case invalidSnapshotName

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "The MultiSwitcher profile schema \(version) is newer than this app supports."
        case .unreadableProfile:
            return "The saved MultiSwitcher profile could not be read. The original file was preserved."
        case .invalidSnapshotName:
            return "A safe name for the Punto backup could not be created."
        }
    }
}

/// Local versioned storage with atomic profile replacement and a previous-generation copy.
public final class ProfileStore: @unchecked Sendable {
    public static let shared = ProfileStore()

    public let rootURL: URL
    public let profileURL: URL
    public let backupsURL: URL

    private let lock = NSRecursiveLock()
    private var cached: MultiSwitcherProfile
    private var loadFailure: Error?

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
                let decoded = try JSONDecoder.multiSwitcher.decode(MultiSwitcherProfile.self, from: data)
                guard decoded.schemaVersion <= MultiSwitcherProfile.currentSchemaVersion else {
                    throw ProfileStoreError.unsupportedSchema(decoded.schemaVersion)
                }
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

    @discardableResult
    public func update(_ change: (inout MultiSwitcherProfile) throws -> Void) throws -> MultiSwitcherProfile {
        lock.lock()
        defer { lock.unlock() }
        if loadFailure != nil { throw ProfileStoreError.unreadableProfile }
        var next = cached
        try change(&next)
        next.schemaVersion = MultiSwitcherProfile.currentSchemaVersion
        try writeAtomically(next)
        cached = next
        return next
    }

    public func reload() throws -> MultiSwitcherProfile {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: profileURL.path) else {
            cached = MultiSwitcherProfile()
            loadFailure = nil
            return cached
        }
        do {
            let data = try Data(contentsOf: profileURL)
            let decoded = try JSONDecoder.multiSwitcher.decode(MultiSwitcherProfile.self, from: data)
            guard decoded.schemaVersion <= MultiSwitcherProfile.currentSchemaVersion else {
                throw ProfileStoreError.unsupportedSchema(decoded.schemaVersion)
            }
            cached = decoded
            loadFailure = nil
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
