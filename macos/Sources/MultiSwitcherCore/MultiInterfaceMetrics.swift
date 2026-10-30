import CoreGraphics
import Foundation

/// Vendored identically by the two independently buildable applications.
public enum MultiInterfaceMetrics {
    public enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 9
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 14
        public static let xl: CGFloat = 16
        public static let panel: CGFloat = 18
    }
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let page: CGFloat = 24
        public static let section: CGFloat = 32
    }
    // A single readable card grid, shared by all settings pages and both apps.
    public static let cardMinimum: CGFloat = 480
    public static let cardIdeal: CGFloat = 600
    public static let settingsMaximum: CGFloat = 640
    public static let complexMaximum = settingsMaximum
    public static let cardPadding: CGFloat = 16
    public static let cardSpacing: CGFloat = 16
    public static func settingsWidth(cardWidth: CGFloat) -> CGFloat {
        sidebarExpanded + 1 + pageInset * 2 + cardWidth
    }
    public static let settingsMinimum = CGSize(width: settingsWidth(cardWidth: cardMinimum), height: 500)
    public static let settingsDefault = CGSize(width: settingsWidth(cardWidth: cardIdeal), height: 620)
    public static let settingsWindowMaximum = CGSize(width: settingsWidth(cardWidth: settingsMaximum), height: 800)
    public static let switcherMaximum = settingsWindowMaximum
    public static let shiftMaximum = settingsWindowMaximum
    public static let editorMaximum = CGSize(width: 1440, height: 960)
    /// Both minimum and maximum shrink on a display smaller than the nominal minimum.
    public static func boundedSize(_ requested: CGSize, minimum: CGSize, maximum: CGSize, available: CGSize) -> CGSize {
        func axis(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat, _ room: CGFloat) -> CGFloat {
            let ceiling = max(1, min(high, room))
            return min(ceiling, max(min(low, ceiling), value.isFinite ? value : low))
        }
        return CGSize(width: axis(requested.width, minimum.width, maximum.width, available.width),
                      height: axis(requested.height, minimum.height, maximum.height, available.height))
    }
    public static let sidebarExpanded: CGFloat = 208
    public static let sidebarCollapsed: CGFloat = 60
    public static let navigationRow: CGFloat = 32
    public static let navigationInset: CGFloat = 12
    public static let pageInset: CGFloat = 24
    public static let formMaximum = settingsMaximum
    public static let sidebarDuration: TimeInterval = 0.26
    public static let hoverDuration: TimeInterval = 0.10
    public static let wheelEnterDuration: TimeInterval = 0.14
    public static let wheelExitDuration: TimeInterval = 0.09
    public static let navigationDuration: TimeInterval = 0.16
    public static let popoverResizeDuration: TimeInterval = 0.20
    public static let sidebarDelta: CGFloat = sidebarExpanded - sidebarCollapsed
    public static func settingsSize(_ expanded: CGSize, progress: CGFloat) -> CGSize {
        CGSize(width: expanded.width - sidebarDelta * (1 - min(1, max(0, progress))), height: expanded.height)
    }
    public static let popoverWidth: CGFloat = 340
    public static let switcherDefault = settingsDefault
    public static let switcherMinimum = settingsMinimum
    public static let shiftDefault = settingsDefault
    public static let shiftMinimum = settingsMinimum

    public static func sidebarWidth(progress: CGFloat) -> CGFloat {
        sidebarCollapsed + (sidebarExpanded - sidebarCollapsed) * min(1, max(0, progress))
    }

    /// Restore the whole window onto a current visible display, including displays
    /// with negative origins. Off-screen and oversized saved frames are recoverable.
    public static func visibleWindowFrame(_ requested: CGRect, screens: [CGRect], minimum: CGSize) -> CGRect {
        let available = screens.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
        guard !available.isEmpty else { return requested }
        let screen = available.max { lhs, rhs in
            let a = lhs.intersection(requested), b = rhs.intersection(requested)
            let areaA = a.isNull ? 0 : a.width * a.height
            let areaB = b.isNull ? 0 : b.width * b.height
            if areaA != areaB { return areaA < areaB }
            let distanceA = pow(lhs.midX - requested.midX, 2) + pow(lhs.midY - requested.midY, 2)
            let distanceB = pow(rhs.midX - requested.midX, 2) + pow(rhs.midY - requested.midY, 2)
            return distanceA > distanceB
        }!
        let width = min(screen.width, max(minimum.width, requested.width.isFinite ? requested.width : minimum.width))
        let height = min(screen.height, max(minimum.height, requested.height.isFinite ? requested.height : minimum.height))
        let x = requested.minX.isFinite ? requested.minX : screen.midX - width / 2
        let y = requested.minY.isFinite ? requested.minY : screen.midY - height / 2
        return CGRect(x: min(max(x, screen.minX), screen.maxX - width),
                      y: min(max(y, screen.minY), screen.maxY - height), width: width, height: height)
    }
}
