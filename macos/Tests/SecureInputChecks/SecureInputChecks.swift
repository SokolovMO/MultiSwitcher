import AppKit
import UserNotifications
import MultiSwitcherCore

@MainActor
private final class TestNoticeGateway: SystemNoticeGateway {
    var onDetails: (() -> Void)?
    var permission: UNAuthorizationStatus = .authorized
    var permissionRequests = 0
    var installed = false
    var failSubmission = false
    var holdSubmission = false
    var heldID: String?
    var continuation: CheckedContinuation<Void, Never>?
    var submitted: [UNNotificationRequest] = []
    var delivered: [String: UNNotificationRequest] = [:]
    var removed: [String] = []
    func install() { installed = true }
    func authorization() async -> UNAuthorizationStatus { permission }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        permission = .authorized
        return true
    }
    func submit(_ request: UNNotificationRequest) async throws {
        if holdSubmission {
            heldID = request.identifier
            await withCheckedContinuation { continuation = $0 }
        }
        if failSubmission { throw NSError(domain: "notice-test", code: 1) }
        submitted.append(request)
        delivered[request.identifier] = request
    }
    func remove(_ identifier: String) {
        removed.append(identifier)
        delivered.removeValue(forKey: identifier)
    }
}

@main struct SecureInputChecks {
    @MainActor static func main() {
        precondition(MultiAuditEnvironment.root != nil, "isolated profile required")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var active = false
        var holder: String? = "Google Chrome"
        var holderReads = 0
        var changes: [SecureInputMonitor.Status] = []
        var notices: [SecureInputMonitor.Status] = []
        var noticesEnabled = true
        let monitor = SecureInputMonitor(readActive: { active }, readHolder: {
            holderReads += 1
            return holder
        }, onChange: { changes.append($0) }, onNotice: {
            guard noticesEnabled else { return false }
            notices.append($0)
            return true
        })
        monitor.sample(now: 0)
        precondition(holderReads == 0 && changes.isEmpty, "stale IORegistry holder treated as an active block")
        active = true
        monitor.sample(now: 1)
        precondition(changes.last?.holderName == "Google Chrome", "menu state did not identify blocker immediately")
        monitor.sample(now: 7)
        precondition(notices.isEmpty, "ordinary password entry produced a notice")
        active = false
        monitor.sample(now: 8)
        precondition(changes.last == .init() && notices.isEmpty, "short password entry did not recover quietly")

        // No keyboard callback or shortcut is invoked anywhere in this sequence.
        active = true
        monitor.sample(now: 10)
        monitor.sample(now: 18)
        precondition(notices.count == 1 && notices.last?.holderName == "Google Chrome",
                     "prolonged Secure Input stayed silent without keyboard events")
        monitor.sample(now: 400)
        precondition(notices.count == 1, "same blocked episode repeated its notice")
        holder = "Terminal"
        monitor.sample(now: 402)
        precondition(changes.last?.holderName == "Terminal" && notices.count == 1,
                     "holder change left stale menu state or repeated the notice")
        active = false
        monitor.sample(now: 403)
        let readsAfterRecovery = holderReads
        monitor.sample(now: 404)
        precondition(holderReads == readsAfterRecovery && !monitor.status.isActive,
                     "recovery kept a stale holder")

        active = true
        holder = nil
        noticesEnabled = false
        monitor.sample(now: 410)
        monitor.sample(now: 418)
        precondition(notices.count == 1 && monitor.status.isActive, "disabled notices hid the blocked state")
        noticesEnabled = true
        monitor.sample(now: 420)
        precondition(notices.count == 2 && notices.last?.holderName == nil,
                     "enabling notices during a block did not explain the unknown holder")
        active = false
        monitor.sample(now: 421)

        // Exercise the scheduled observer itself, without keyboard input.
        active = true
        holder = "Google Chrome"
        monitor.start()
        precondition(monitor.status.isActive, "start did not sample the current block")
        active = false
        let deadline = Date().addingTimeInterval(3)
        while monitor.status.isActive && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(!monitor.status.isActive, "timer did not detect recovery without keyboard events")
        monitor.stop()

        if let iconPath = ProcessInfo.processInfo.environment["MULTI_NOTICE_ICON"],
           let icon = NSImage(contentsOfFile: iconPath) { NSApp.applicationIconImage = icon }
        func waitUntil(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(condition(), "asynchronous notification check timed out")
        }
        let gateway = TestNoticeGateway()
        precondition(NativeSystemNoticeGateway.presentationOptions(alertStyle: .alert).contains(.banner),
                     "persistent system alert preference suppressed foreground delivery")
        precondition(NativeSystemNoticeGateway.presentationOptions(alertStyle: .none) == [.list],
                     "disabled banners were overridden")
        var settingsOpened = 0
        var detailsOpened = 0
        let notice = SecureInputNotice(gateway: gateway, openSettings: { settingsOpened += 1 })
        notice.onDetails = { detailsOpened += 1 }
        notice.install()
        precondition(gateway.installed, "notification response handler was not installed at launch")
        notice.show(title: "Paused", body: "Google Chrome protects input")
        waitUntil { !notice.isDelivering }
        precondition(notice.lastDelivery == .system && gateway.submitted.count == 1,
                     "authorized notice did not use Notification Center")
        let request = gateway.submitted[0]
        precondition(request.trigger == nil && request.content.sound == nil && request.content.attachments.isEmpty,
                     "notice adds an unsolicited sound or duplicates the system app icon")
        precondition(request.content.categoryIdentifier == NativeSystemNoticeGateway.category,
                     "system banner has no details action")
        precondition(gateway.permissionRequests == 0, "blocked input unexpectedly requested permission")
        gateway.onDetails?()
        precondition(detailsOpened == 1, "system details action did not open recovery help")
        notice.hide()
        precondition(gateway.delivered.isEmpty, "recovery left a stale notification in Notification Center")

        // add() may finish after recovery and even after a new episode begins.
        gateway.holdSubmission = true
        notice.show(title: "Old episode", body: "old")
        waitUntil { gateway.continuation != nil }
        let oldID = gateway.heldID!
        notice.hide()
        gateway.holdSubmission = false
        notice.show(title: "New episode", body: "new")
        waitUntil { !notice.isDelivering }
        gateway.continuation?.resume()
        gateway.continuation = nil
        waitUntil { gateway.removed.filter { $0 == oldID }.count >= 2 }
        precondition(gateway.delivered.count == 1 && gateway.delivered.values.first?.content.title == "New episode",
                     "late delivery left a stale warning or removed the new episode")
        notice.hide()

        let windowCount = NSApp.windows.count
        var statuses: [SecureInputNotice.Delivery] = []
        notice.onStatus = { statuses.append($0) }
        gateway.permission = .notDetermined
        notice.show(title: "Paused", body: "Google Chrome protects input")
        waitUntil { !notice.isDelivering }
        precondition(notice.lastDelivery == .permissionRequired && gateway.permissionRequests == 0,
                     "blocked password field requested notification permission")
        precondition(NSApp.windows.count == windowCount, "missing permission created an imitation system banner")
        gateway.permission = .denied
        notice.show(title: "Paused", body: "Google Chrome protects input")
        waitUntil { !notice.isDelivering }
        precondition(statuses.last == .denied && NSApp.windows.count == windowCount,
                     "denied notifications produced a custom overlay instead of persistent status")
        notice.configureFromSettings()
        waitUntil { settingsOpened == 1 }
        gateway.permission = .notDetermined
        notice.configureFromSettings()
        waitUntil { gateway.permissionRequests == 1 && gateway.submitted.last?.identifier == "com.multiswitcher.notification-test" }
        precondition(gateway.submitted.last?.content.categoryIdentifier == "", "test notification opens a stale Secure Input explanation")
        gateway.failSubmission = true
        notice.show(title: "Paused", body: "Google Chrome protects input")
        waitUntil { !notice.isDelivering }
        precondition(notice.lastDelivery == .failed && statuses.last == .failed && NSApp.windows.count == windowCount,
                     "delivery failure created an imitation system banner or hid the error status")
        gateway.failSubmission = false

        let learning = LearningNotice(gateway: gateway)
        learning.onStatus = { statuses.append($0) }
        gateway.permission = .denied
        let submittedBefore = gateway.submitted.count
        learning.show(title: "Learning", body: "A generic result", near: nil)
        waitUntil { !learning.isDelivering }
        precondition(statuses.last == .denied && gateway.submitted.count == submittedBefore && NSApp.windows.count == windowCount,
                     "learning bypassed the user's notification preference")
        gateway.permission = .authorized
        for language in L10n.supportedLanguages.sorted() {
            SettingsManager.shared.interfaceLanguage = language
            L10n.reloadLanguage()
            precondition(L10n.securePausedTitle.count < 65 && L10n.securePausedBody.count < 170,
                         "notification copy is too long to scan")
            learning.show(title: L10n.learningManualCandidateTitle,
                          body: L10n.learningManualCandidateNoticeBody, near: nil)
            waitUntil { !learning.isDelivering }
            let latest = gateway.submitted.last!
            precondition(latest.identifier == "com.multiswitcher.feedback" && latest.content.sound == nil && latest.content.categoryIdentifier.isEmpty,
                         "learning feedback is noisy, uncoalesced or routes to Secure Input help")
        }
        SettingsManager.shared.interfaceLanguage = "ru"
        L10n.reloadLanguage()
        precondition(L10n.commonOkay == "понятно", "Russian dialogs fall back to English OK")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let alert = GraphiteAlert()
            alert.messageText = L10n.securePausedTitle
            alert.informativeText = String(format: L10n.securePausedDetails, "Google Chrome")
            alert.addButton(withTitle: L10n.commonOkay)
            alert.window.appearance = NSAppearance(named: appearance)
            let originalCell = alert.buttons[0].cell
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            DesignStyler.apply(material)
            precondition(material.subviews.isEmpty && material.blendingMode == .behindWindow,
                         "a gray layer was inserted over the native material")
            let closeTimer = Timer(timeInterval: 0.1, repeats: false) { _ in
                MainActor.assumeIsolated { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
            }
            RunLoop.main.add(closeTimer, forMode: .modalPanel)
            _ = alert.runModal()
            precondition(alert.buttons[0].cell === originalCell && alert.buttons[0].bezelColor == nil,
                         "NSAlert's native button renderer was replaced")
            alert.window.orderOut(nil)
        }
        notice.hide()
        print("SecureInputChecks PASS: native-only delivery, denied/missing permission and failure status without overlays, recovery cleanup, cancellation race, generic learning notifications, 16 languages and real NSAlert behavior")
    }
}
