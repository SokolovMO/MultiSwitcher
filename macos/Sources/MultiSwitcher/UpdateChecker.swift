#if !canImport(Sparkle)
import Foundation

/// Development builds do not make network requests or install updates.
@MainActor
enum UpdateChecker {
    static var isConfigured: Bool { false }
    static func checkOnLaunch() {}
    static func checkPeriodic() {}
    static func checkNow() {}
    static func channelDidChange() {}
    static func automaticChecksDidChange(_ enabled: Bool) {}
}
#endif
