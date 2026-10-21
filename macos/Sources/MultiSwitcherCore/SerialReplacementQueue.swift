import Foundation

/// Exact undo direction for a committed buffer replacement. Keeps the original
/// operation identity through repeated Option toggles so only the return-to-source
/// transition can count as an undo for learning.
public struct BufferReplacementLifecycle: Equatable, Sendable {
    public private(set) var operationID: String?
    public private(set) var isConverted = false

    public init() {}

    public mutating func commit(operationID: String) {
        guard !operationID.isEmpty else {
            clear()
            return
        }
        self.operationID = operationID
        isConverted = true
    }

    /// Returns the operation ID only when the original text has been restored.
    public mutating func toggle() -> String? {
        guard let operationID else { return nil }
        isConverted.toggle()
        return isConverted ? nil : operationID
    }

    public mutating func clear() {
        operationID = nil
        isConverted = false
    }
}

/// Bounded FIFO state used by text replacement adapters. The queue stores intent;
/// callers must still revalidate the field and captured text immediately before apply.
public struct SerialReplacementQueue<Element> {
    public let capacity: Int
    private var pending: [Element] = []
    public private(set) var isActive = false

    public init(capacity: Int = 8) {
        precondition(capacity > 0, "Serial replacement queue capacity must be positive")
        self.capacity = capacity
    }

    public var pendingCount: Int { pending.count }

    /// Capacity limits waiting work, not the single operation already in flight.
    @discardableResult
    public mutating func enqueue(_ element: Element) -> Bool {
        guard pending.count < capacity else { return false }
        pending.append(element)
        return true
    }

    /// Starts at most one operation and preserves insertion order.
    public mutating func beginNext() -> Element? {
        guard !isActive, !pending.isEmpty else { return nil }
        isActive = true
        return pending.removeFirst()
    }

    public mutating func finishCurrent() {
        guard isActive else { return }
        isActive = false
    }
}
