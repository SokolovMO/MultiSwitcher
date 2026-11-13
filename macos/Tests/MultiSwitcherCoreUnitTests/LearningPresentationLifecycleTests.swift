import XCTest
import MultiSwitcherCore

final class LearningPresentationLifecycleTests: XCTestCase {
    func testCandidateConfirmationAndForgetPreserveOtherRuleSources() throws {
        var profile = MultiSwitcherProfile(rules: [
            ProfileRule(pattern: "manual-only", origin: .user),
            ProfileRule(pattern: "import-only", origin: .punto),
        ])
        let baseline = profile.rules
        _ = LearningEngine.recordManualOptionRoundTrip(word: "Foobar", in: &profile)
        XCTAssertFalse(LearningEngine.confirmManualCandidate(word: "Foobar", in: &profile))
        _ = LearningEngine.recordManualOptionRoundTrip(word: "Foobar", in: &profile)
        XCTAssertEqual(profile.rules, baseline, "manual evidence remains a candidate until confirmed")
        XCTAssertTrue(LearningEngine.confirmManualCandidate(word: "Foobar", in: &profile))
        XCTAssertEqual(profile.rules.filter { $0.origin == .learned }.count, 1)
        XCTAssertTrue(profile.learning.first { $0.word == "Foobar" }?.isExcluded == true)
        let export = try UserRuleFileCodec.encode(profile.rules.filter { $0.origin == .user })
        XCTAssertEqual(try UserRuleFileCodec.decode(export).count, 1)
        LearningEngine.forget(word: "Foobar", in: &profile)
        XCTAssertEqual(profile.rules, baseline)
        XCTAssertTrue(profile.learning.isEmpty)
    }

    func testFreshInstallationHasNoPersonalRulesOrLearning() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(rootURL: directory)
        XCTAssertTrue(store.current.rules.isEmpty)
        XCTAssertTrue(store.current.learning.isEmpty)
    }
}
