import AppKit
@preconcurrency import UserNotifications

@MainActor
protocol SystemNoticeGateway: AnyObject {
    var onDetails: (() -> Void)? { get set }
    func install()
    func authorization() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func submit(_ request: UNNotificationRequest) async throws
    func remove(_ identifier: String)
}

/// App icon, layout, placement, accessibility, Focus and dismissal belong to macOS,
/// exactly as in MultiShift's OperationNotifications.
@MainActor
final class NativeSystemNoticeGateway: NSObject, SystemNoticeGateway, UNUserNotificationCenterDelegate {
    static let shared = NativeSystemNoticeGateway()
    static let category = "MULTISWITCHER_SECURE_INPUT"
    static let detailsAction = "MULTISWITCHER_SECURE_INPUT_DETAILS"
    var onDetails: (() -> Void)?
    private lazy var center: UNUserNotificationCenter = {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    func install() { _ = center }

    func authorization() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func submit(_ request: UNNotificationRequest) async throws {
        let details = UNNotificationAction(identifier: Self.detailsAction, title: L10n.noticeDetails,
                                           options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [details], intentIdentifiers: [])
        ])
        try await center.add(request)
    }

    func remove(_ identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completion: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        center.getNotificationSettings { settings in
            completion(Self.presentationOptions(alertStyle: settings.alertStyle))
        }
    }

    nonisolated static func presentationOptions(alertStyle: UNAlertStyle) -> UNNotificationPresentationOptions {
        alertStyle == .none ? [.list] : [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completion: @escaping () -> Void) {
        let action = response.actionIdentifier
        guard response.notification.request.content.categoryIdentifier == "MULTISWITCHER_SECURE_INPUT" else { completion(); return }
        if action == UNNotificationDefaultActionIdentifier || action == "MULTISWITCHER_SECURE_INPUT_DETAILS" {
            Task { @MainActor [weak self] in self?.onDetails?() }
        }
        completion()
    }
}

@MainActor
final class SecureInputNotice {
    enum Delivery: Equatable { case ready, system, permissionRequired, denied, failed }
    private let gateway: any SystemNoticeGateway
    private let openSettings: () -> Void
    private var deliveryTask: Task<Void, Never>?
    private var requestID: String?
    private(set) var isDelivering = false
    private(set) var lastDelivery: Delivery? { didSet { if let lastDelivery { onStatus?(lastDelivery) } } }
    var onDetails: (() -> Void)?
    var onStatus: ((Delivery) -> Void)?

    init(gateway: (any SystemNoticeGateway)? = nil, openSettings: @escaping () -> Void = {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.multiswitcher.app")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }) {
        self.gateway = gateway ?? NativeSystemNoticeGateway.shared
        self.openSettings = openSettings
        self.gateway.onDetails = { [weak self] in self?.onDetails?() }
    }

    func install() {
        gateway.install()
        Task { [weak self] in
            guard let self else { return }
            let permission = await self.gateway.authorization()
            if self.lastDelivery == nil { self.lastDelivery = Self.status(for: permission) }
        }
    }

    static func status(for permission: UNAuthorizationStatus) -> Delivery {
        switch permission {
        case .authorized, .provisional: return .ready
        case .notDetermined: return .permissionRequired
        default: return .denied
        }
    }


    func show(title: String, body: String) {
        hide()
        let identifier = "com.multiswitcher.secure-input.\(UUID().uuidString)"
        requestID = identifier
        isDelivering = true
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            let permission = await self.gateway.authorization()
            guard !Task.isCancelled else { return }
            if permission == .authorized || permission == .provisional {
                do {
                    try await self.gateway.submit(Self.request(id: identifier, title: title, body: body))
                    // Recovery can race add(). Withdraw only that request, never
                    // a later episode's notification.
                    guard !Task.isCancelled else { self.gateway.remove(identifier); return }
                    self.lastDelivery = .system
                } catch {
                    guard !Task.isCancelled else { return }
                    self.lastDelivery = .failed
                }
            } else {
                // A password field must never trigger a permission dialog.
                // Only the explicit settings/test button requests permission.
                self.lastDelivery = Self.status(for: permission)
            }
            self.isDelivering = false
        }
    }

    func hide() {
        deliveryTask?.cancel()
        deliveryTask = nil
        isDelivering = false
        if let requestID { gateway.remove(requestID) }
        requestID = nil
    }

    /// Explicit user action: request permission if needed, then send a quiet test.
    func configureFromSettings() {
        Task { [weak self] in
            guard let self else { return }
            let permission = await self.gateway.authorization()
            do {
                if permission == .denied { self.lastDelivery = .denied; self.openSettings(); return }
                if permission == .notDetermined {
                    guard try await self.gateway.requestAuthorization() else { self.lastDelivery = .denied; return }
                }
                let request = Self.request(id: "com.multiswitcher.notification-test", title: L10n.noticeTestTitle,
                                           body: L10n.noticeTestBody)
                try await self.gateway.submit(request)
                self.lastDelivery = .system
            } catch {
                self.lastDelivery = .failed
            }
        }
    }

    static func request(id: String, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = id == "com.multiswitcher.notification-test" ? "" : NativeSystemNoticeGateway.category
        content.threadIdentifier = "com.multiswitcher.secure-input"
        content.sound = nil
        return UNNotificationRequest(identifier: id, content: content, trigger: nil)
    }

}
