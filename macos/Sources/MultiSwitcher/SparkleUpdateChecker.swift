#if canImport(Sparkle)
import AppKit
import Foundation
import MultiSwitcherCore
import Sparkle

@MainActor
private final class MultiSwitcherUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    @objc(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        (NSApplication.shared.delegate as? AppDelegate)?.postponeUpdateRelaunch(installHandler) ?? false
    }
}

/// Sparkle is linked only in distribution builds. Developer review builds do not
/// perform network update checks or contain Sparkle's updater services.
@MainActor
enum UpdateChecker {
    private static var updaterDelegate: MultiSwitcherUpdaterDelegate?
    private static var controller: SPUStandardUpdaterController?
    private static var reviewDriver: SPUStandardUserDriver?

    /// Real Sparkle UI on an isolated profile. No updater/download/install object exists.
    static func auditReadyToInstall(to directory: URL) {
        guard MultiAuditEnvironment.root != nil else { return }
        let driver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
        reviewDriver = driver
        @MainActor final class Result { var actionRouted = false }
        let result = Result()
        Task { @MainActor in
            _ = await driver.showReadyToInstallAndRelaunch()
            result.actionRouted = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "SUStatus" }),
                  let root = window.contentView else { fatalError("Sparkle status window missing") }
            @MainActor func buttons(_ view: NSView) -> [NSButton] {
                (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
            }
            guard let button = buttons(root).first else { fatalError("Sparkle action missing") }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            let framework = Bundle(for: SPUStandardUserDriver.self)
            let expected = framework.localizedString(forKey: "Install and Relaunch", value: nil, table: "Sparkle")
            for theme in [InterfaceTheme.light, .dark] {
                DesignTheme.shared.preference = theme
                try? await Task.sleep(for: .milliseconds(200))
                SettingsWindowController.captureWindow(window, to: directory.appendingPathComponent("update-\(theme.rawValue).png").path)
            }
            let nativeCell = !String(describing: type(of: button.cell!)).contains("Graphite")
            precondition(nativeCell && button.title == expected && button.keyEquivalent == "\r" && button.isEnabled)
            button.performClick(nil)
            try? await Task.sleep(for: .milliseconds(100))
            precondition(result.actionRouted, "Sparkle action was lost during styling")
            let report: [String: Any] = ["language": L10n.languageCode,
                "frameworkLanguages": framework.preferredLocalizations,
                "buttonTitle": button.title, "expectedTitle": expected,
                "nativeCell": nativeCell, "returnKey": button.keyEquivalent == "\r",
                "actionRouted": result.actionRouted, "realUpdaterCreated": false,
                "buttonWidth": button.bounds.width]
            try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("update-ui-results.json"))
            NSApp.terminate(nil)
        }
    }

    static var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil else { return false }
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
