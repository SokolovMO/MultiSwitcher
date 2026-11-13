import CoreGraphics
import XCTest
@testable import MultiSwitcherCore

final class InterfaceGeometryTests: XCTestCase {
    func testCompactWindowPreservesTheDetailWidthAtEveryPhase() {
        for phase in stride(from: CGFloat(0), through: 1, by: 0.1) {
            for expanded in [MultiInterfaceMetrics.switcherDefault, MultiInterfaceMetrics.shiftDefault] {
                let size = MultiInterfaceMetrics.settingsSize(expanded, progress: phase)
                XCTAssertEqual(size.width - MultiInterfaceMetrics.sidebarWidth(progress: phase), expanded.width - 208, accuracy: 0.001)
                XCTAssertEqual(size.height, expanded.height)
            }
        }
        XCTAssertEqual(MultiInterfaceMetrics.settingsSize(MultiInterfaceMetrics.switcherMinimum, progress: 0).width, 589)
        XCTAssertEqual(MultiInterfaceMetrics.settingsSize(MultiInterfaceMetrics.shiftMinimum, progress: 0).width, 589)
    }
    func testSidebarHasBoundedContinuousWidthsForReversal() {
        XCTAssertEqual(MultiInterfaceMetrics.sidebarWidth(progress: 0), 60)
        XCTAssertEqual(MultiInterfaceMetrics.sidebarWidth(progress: 1), 208)
        let phases: [CGFloat] = [0, 0.1, 0.4, 0.3, 0.7, 1, 1.5, -1]
        for phase in phases {
            let width = MultiInterfaceMetrics.sidebarWidth(progress: phase)
            XCTAssertTrue((60...208).contains(width))
            XCTAssertGreaterThanOrEqual(width - 24, 36, "selection must contain the icon target")
        }
        XCTAssertEqual(MultiInterfaceMetrics.sidebarWidth(progress: 0.5), 134)
    }
    func testRestoredWindowFitsDisconnectedMonitorAndSmallDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 760)
        let saved = CGRect(x: 2400, y: 1000, width: 1800, height: 1200)
        let result = MultiInterfaceMetrics.visibleWindowFrame(saved, screens: [screen], minimum: CGSize(width: 700, height: 480))
        XCTAssertTrue(screen.contains(result))
        XCTAssertEqual(result.size, screen.size)
    }
    func testNegativeOriginDisplayIsPreservedAndPartialFrameClamped() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = CGRect(x: -1300, y: 700, width: 860, height: 600)
        let result = MultiInterfaceMetrics.visibleWindowFrame(saved, screens: [right, left], minimum: CGSize(width: 700, height: 480))
        XCTAssertTrue(left.contains(result))
        XCTAssertEqual(result.minX, saved.minX)
        XCTAssertEqual(result.maxY, left.maxY)
    }
    func testUsefulMaximumPreventsUnboundedSettingsGrowth() {
        for (minimum, ideal, maximum) in [
            (MultiInterfaceMetrics.switcherMinimum, MultiInterfaceMetrics.switcherDefault, MultiInterfaceMetrics.switcherMaximum),
            (MultiInterfaceMetrics.shiftMinimum, MultiInterfaceMetrics.shiftDefault, MultiInterfaceMetrics.shiftMaximum)
        ] {
            XCTAssertEqual(MultiInterfaceMetrics.boundedSize(CGSize(width: 8000, height: 6000), minimum: minimum,
                maximum: maximum, available: CGSize(width: 4000, height: 2000)), maximum)
            XCTAssertEqual(MultiInterfaceMetrics.boundedSize(ideal, minimum: minimum, maximum: maximum,
                available: maximum), ideal)
            XCTAssertEqual(MultiInterfaceMetrics.boundedSize(.zero, minimum: minimum, maximum: maximum,
                available: maximum), minimum)
        }
    }
    func testSmallWorkingAreaWinsOverNominalMinimum() {
        let room = CGSize(width: 640, height: 400)
        let actual = MultiInterfaceMetrics.boundedSize(CGSize(width: 880, height: 620),
            minimum: MultiInterfaceMetrics.switcherMinimum, maximum: MultiInterfaceMetrics.switcherMaximum, available: room)
        XCTAssertEqual(actual, room)
        let invalid = MultiInterfaceMetrics.boundedSize(CGSize(width: CGFloat.infinity, height: CGFloat.nan),
            minimum: MultiInterfaceMetrics.shiftMinimum, maximum: MultiInterfaceMetrics.shiftMaximum,
            available: CGSize(width: 1500, height: 1000))
        XCTAssertEqual(invalid, MultiInterfaceMetrics.shiftMinimum)
    }
    func testSemanticSurfaceRadiiAreOrderedAndBounded() {
        let radii = [MultiInterfaceMetrics.Radius.xs, MultiInterfaceMetrics.Radius.sm,
            MultiInterfaceMetrics.Radius.md, MultiInterfaceMetrics.Radius.lg,
            MultiInterfaceMetrics.Radius.xl, MultiInterfaceMetrics.Radius.panel]
        XCTAssertEqual(radii, radii.sorted())
        XCTAssertEqual(radii, [6, 9, 10, 14, 16, 18])
    }

}
