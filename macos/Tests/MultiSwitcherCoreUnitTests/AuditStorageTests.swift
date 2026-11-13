import Foundation
import XCTest
@testable import MultiSwitcherCore

final class AuditStorageTests: XCTestCase {
    func testNewAuditDirectoryKeepsItsIdentityOnRelaunch() throws {
        let parent = URL(fileURLWithPath: "/private/tmp/multi-audit-identity-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let path = parent.appendingPathComponent("data", isDirectory: true).path
        let firstLaunch = try MultiAuditEnvironment.preparedRoot(at: path)
        let relaunch = try MultiAuditEnvironment.preparedRoot(at: path)
        XCTAssertEqual(firstLaunch.path, relaunch.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstLaunch.path))
    }
}
