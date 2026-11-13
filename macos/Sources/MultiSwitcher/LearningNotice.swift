import AppKit
import UserNotifications

/// Brief background feedback uses the same system renderer as Secure Input.
/// Callers supply generic messages: typed words never enter notification history.
@MainActor
final class LearningNotice {
    private let gateway: any SystemNoticeGateway
    private var pendingNotice: (title: String, body: String)?
    var onStatus: ((SecureInputNotice.Delivery) -> Void)?
    private(set) var isDelivering = false

    init(gateway: (any SystemNoticeGateway)? = nil) {
        self.gateway = gateway ?? NativeSystemNoticeGateway.shared
    }

    func show(title: String, body: String, near button: NSStatusBarButton?) {
        pendingNotice = (title, body)
        guard !isDelivering else { return }
        isDelivering = true
        Task { [weak self] in
            guard let self else { return }
            // Serialize actual submissions. A late completion for older feedback
            // cannot overwrite a newer result with the same coalescing identifier.
            while let message = self.pendingNotice {
                self.pendingNotice = nil
                let permission = await self.gateway.authorization()
                guard self.pendingNotice == nil else { continue }
                guard permission == .authorized || permission == .provisional else {
                    self.onStatus?(SecureInputNotice.status(for: permission))
                    continue
                }
                let content = UNMutableNotificationContent()
                content.title = message.title
                content.body = message.body
                content.threadIdentifier = "com.multiswitcher.feedback"
                content.sound = nil
                do {
                    try await self.gateway.submit(UNNotificationRequest(
                        identifier: "com.multiswitcher.feedback", content: content, trigger: nil))
                    self.onStatus?(.system)
                } catch {
                    self.onStatus?(.failed)
                }
            }
            self.isDelivering = false
        }
    }
}
