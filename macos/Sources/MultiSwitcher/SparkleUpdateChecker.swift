#if canImport(Sparkle)
import AppKit
import Foundation
import MultiSwitcherCore
import Sparkle

@MainActor
private final class MultiSwitcherUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        SettingsManager.shared.updateChannel == .beta ? ["beta"] : []
    }
}

/// Sparkle is linked only in distribution builds. Developer review builds do not
/// perform network update checks or contain Sparkle's updater services.
@MainActor
enum UpdateChecker {
    private static var updaterDelegate: MultiSwitcherUpdaterDelegate?
    private static var controller: SPUStandardUpdaterController?

    static var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https",
              url.host == "sokolovmo.github.io",
              url.path == "/multi-releases/MultiSwitcher/appcast.xml" else { return false }
        return true
    }

    static func checkOnLaunch() {
        guard isConfigured else { return }
        ensureController()
        controller?.updater.automaticallyChecksForUpdates = SettingsManager.shared.checkUpdatesEnabled
    }

    /// Scheduling and retry backoff are owned by Sparkle; the app must not poll in parallel.
    static func checkPeriodic() {}

    static func checkNow() {
        guard isConfigured else { return }
        ensureController()
        controller?.checkForUpdates(nil)
    }

    static func channelDidChange() {
        guard isConfigured else { return }
        ensureController()
        controller?.updater.resetUpdateCycleAfterShortDelay()
    }

    static func automaticChecksDidChange(_ enabled: Bool) {
        guard isConfigured else { return }
        ensureController()
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    private static func ensureController() {
        guard MultiAuditEnvironment.root == nil, controller == nil else { return }
        let delegate = MultiSwitcherUpdaterDelegate()
        updaterDelegate = delegate // SPUStandardUpdaterController holds delegates weakly.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        controller?.updater.automaticallyChecksForUpdates = SettingsManager.shared.checkUpdatesEnabled
        // Never silently install an update. Sparkle presents its standard confirmation UI.
        controller?.updater.automaticallyDownloadsUpdates = false
        controller?.startUpdater()
    }
}
#endif
