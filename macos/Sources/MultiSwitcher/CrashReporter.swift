import Foundation
import MultiSwitcherCore

#if canImport(Sentry)
import Sentry
#endif

@MainActor
enum CrashReporter {
    private static let consentKey = "com.multiswitcher.crashReportsConsent"
    private static let revokedAtKey = "com.multiswitcher.crashReportsRevokedAt"
    private static var defaults: UserDefaults { SettingsManager.interfaceDefaults }
    private static var started = false

    static var isAvailable: Bool {
        #if canImport(Sentry)
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "MSCrashReportDSN") as? String else {
            return false
        }
        guard let url = URL(string: dsn), url.scheme == "https", url.host != nil,
              url.user?.isEmpty == false, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.range(of: "^/[0-9]+$", options: .regularExpression) != nil else { return false }
        return true
        #else
        return false
        #endif
    }

    static var isEnabled: Bool {
        defaults.bool(forKey: consentKey)
    }

    /// Consent is off for new installs. The SDK is not initialized unless the
    /// user explicitly opts in and a release build has a configured endpoint.
    static func startIfConsented() {
        guard MultiAuditEnvironment.root == nil, isAvailable, isEnabled else { return }
        #if canImport(Sentry)
        start()
        #endif
    }

    static func setConsent(_ enabled: Bool) {
        defaults.set(enabled, forKey: consentKey)
        if enabled {
            startIfConsented()
        } else {
            defaults.set(Date(), forKey: revokedAtKey)
            #if canImport(Sentry)
            if started {
                SentrySDK.close()
                started = false
            }
            #endif
        }
    }

    #if canImport(Sentry)
    private static func start() {
        guard !started,
              isEnabled,
              let dsn = Bundle.main.object(forInfoDictionaryKey: "MSCrashReportDSN") as? String,
              !dsn.isEmpty else { return }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let channel = (Bundle.main.object(forInfoDictionaryKey: "MSUpdateChannel") as? String) ?? "stable"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = "MultiSwitcher@\(version)+\(build)"
            options.environment = channel
            options.debug = false
            options.sendDefaultPii = false
            options.enableCrashHandler = true
            options.enableMemoryIntrospection = false
            options.enableAutoSessionTracking = false
            options.enableAutoBreadcrumbTracking = false
            options.enableAutoPerformanceTracing = false
            options.tracesSampleRate = 0
            options.beforeSend = { event in
                guard defaults.bool(forKey: consentKey) else { return nil }
                if let revokedAt = defaults.object(forKey: revokedAtKey) as? Date {
                    // If Sentry cannot provide a timestamp, do not assume the event
                    // occurred after consent was revoked.
                    guard let occurredAt = event.timestamp, occurredAt > revokedAt else {
                        return nil
                    }
                }

                // Keep only an unhandled native crash, not ordinary captured errors.
                guard let exceptions = event.exceptions,
                      exceptions.contains(where: { $0.mechanism?.handled?.boolValue == false }) else {
                    return nil
                }

                // This app handles sensitive text input. Only version, OS version,
                // exception type, and stack frames are retained. User-facing error
                // strings, arbitrary scope data, requests, threads, and breadcrumbs
                // can never leave the device.
                event.message = nil
                event.error = nil
                event.logger = "multiswitcher.crash"
                event.serverName = nil
                event.transaction = nil
                event.request = nil
                event.user = nil
                event.extra = nil
                event.modules = nil
                event.fingerprint = nil
                event.context = ["os": ["name": "macOS", "version": osVersion]]
                event.tags = ["release_channel": channel]
                event.threads = nil
                event.breadcrumbs = []
                event.exceptions?.forEach { exception in
                    exception.value = nil
                    exception.mechanism = nil
                    exception.threadId = nil
                }
                return event
            }
        }
        started = true
    }
    #endif
}
