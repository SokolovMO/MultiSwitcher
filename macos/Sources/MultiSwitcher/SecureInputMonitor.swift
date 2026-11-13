import Foundation

/// Secure Input can stop delivery to the keyboard tap altogether. Observe it
/// independently, without reading keystrokes or waiting for a conversion shortcut.
@MainActor
final class SecureInputMonitor {
    struct Status: Equatable {
        var isActive = false
        var holderName: String?
    }

    private let readActive: () -> Bool
    private let readHolder: () -> String?
    private let onChange: (Status) -> Void
    private let onNotice: (Status) -> Bool
    private var timer: Timer?
    private var activeSince: TimeInterval?
    private var noticeDelivered = false
    private(set) var status = Status()

    init(readActive: @escaping () -> Bool = { AutoSwitchPolicy.secureInputActive },
         readHolder: @escaping () -> String? = { AutoSwitchPolicy.secureInputHolderName() },
         onChange: @escaping (Status) -> Void,
         onNotice: @escaping (Status) -> Bool) {
        self.readActive = readActive
        self.readHolder = readHolder
        self.onChange = onChange
        self.onNotice = onNotice
    }

    func start() {
        stop()
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sample(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let active = readActive()
        // IORegistry can retain an old holder PID after Secure Input ends. Only
        // resolve it while the authoritative system API reports an active block.
        let next = Status(isActive: active, holderName: active ? readHolder() : nil)
        if active {
            if activeSince == nil { activeSince = now }
        } else {
            activeSince = nil
            noticeDelivered = false
        }
        if next != status {
            status = next
            onChange(next)
        }
        // Ordinary password entry should stay quiet. Explain a prolonged block
        // once per episode; a disabled notice can be enabled during that episode.
        if let activeSince, now - activeSince >= 8, !noticeDelivered {
            noticeDelivered = onNotice(next)
        }
    }
}
