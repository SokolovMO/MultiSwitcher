import Foundation

public struct SettingsCardFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// Computes the smallest downward movement that gives a settings card a consistent
/// vertical gutter from every existing card sharing its horizontal span.
public enum SettingsCardLayoutPolicy {
    /// Returns the lower-left y origin that keeps fixed-height content attached
    /// to the top edge of a taller AppKit container.
    public static func topAlignedOriginY(containerHeight: Double, contentHeight: Double) -> Double {
        max(0, max(0, containerHeight) - max(0, contentHeight))
    }

    /// Returns an inset fill frame for a page that should retain equal breathing
    /// room above and below its content, even when the available window is short.
    public static func insetFillFrame(containerHeight: Double, inset: Double) -> (originY: Double, height: Double) {
        let height = max(0, containerHeight)
        let resolvedInset = min(max(0, inset), height / 2)
        return (resolvedInset, max(0, height - 2 * resolvedInset))
    }

    /// Returns how far a legacy, bottom-origin card must move down to stay inside
    /// its page when localized text or fixed controls extend beyond the top edge.
    public static func downwardShiftToFitTop(containerHeight: Double, contentMaxY: Double) -> Double {
        max(0, max(0, contentMaxY) - max(0, containerHeight))
    }

    /// Keeps the scroll document large enough for both its viewport and every
    /// measured settings page. Dynamic status rows can make one page taller after
    /// the window has already been created.
    public static func documentHeight(
        viewportHeight: Double,
        baselineHeight: Double,
        pageHeights: [Double]
    ) -> Double {
        max(
            max(0, viewportHeight),
            max(max(0, baselineHeight), pageHeights.map { max(0, $0) }.max() ?? 0)
        )
    }

    public static func downwardShift(
        for frame: SettingsCardFrame,
        existingFrames: [SettingsCardFrame],
        gutter: Double
    ) -> Double {
        var lowestNeighbor: Double?
        for existing in existingFrames where frame.maxX > existing.x && frame.x < existing.maxX {
            lowestNeighbor = lowestNeighbor.map { min($0, existing.y) } ?? existing.y
        }
        guard let lowestNeighbor else { return 0 }
        return max(0, frame.maxY - (lowestNeighbor - max(0, gutter)))
    }
}
