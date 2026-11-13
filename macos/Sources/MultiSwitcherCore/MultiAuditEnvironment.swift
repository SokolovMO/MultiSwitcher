import CryptoKit
import Foundation

/// Audit storage is independent from visual probes, so functional launches keep real behavior.
public enum MultiAuditEnvironment {
    public static let root: URL? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MULTI_AUDIT_DATA_ROOT"] ?? environment["MULTI_ECOSYSTEM_REVIEW"]
                ?? environment["MULTISWITCHER_UI_REVIEW"] ?? environment["MULTISWITCHER_PERMISSION_REVIEW"] else { return nil }
        // An invalid test configuration must never fall back to production storage.
        guard path.hasPrefix("/") else { fatalError("Audit data root must be an absolute path") }
        do { return try preparedRoot(at: path) }
        catch { fatalError("Audit data root could not be prepared: \(error)") }
    }()
    // Foundation resolves symlinks differently for a missing directory. Create it
    // before standardizing so /private/tmp and /tmp keep one namespace on relaunch.
    static func preparedRoot(at path: String) throws -> URL {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.standardizedFileURL
    }
    public static var isFunctional: Bool {
        ProcessInfo.processInfo.environment["MULTI_AUDIT_DATA_ROOT"] != nil
            && ProcessInfo.processInfo.environment["MULTI_ECOSYSTEM_REVIEW"] == nil
    }
    public static var namespace: String? {
        guard let root else { return nil }
        return SHA256.hash(data: Data(root.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    public static func windowAutosaveName(_ base: String) -> String {
        namespace.map { base + ".audit." + $0 } ?? base
    }
    public static func defaults(appID: String) -> UserDefaults {
        guard let namespace else { return UserDefaults(suiteName: appID) ?? .standard }
        return UserDefaults(suiteName: appID + ".audit." + namespace)!
    }
}
