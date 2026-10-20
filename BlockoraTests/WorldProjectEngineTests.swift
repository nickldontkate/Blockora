import XCTest
@testable import Blockora

final class WorldProjectEngineTests: XCTestCase {
    private func state(contributed: ResourceBag) -> WorldProjectState {
        WorldProjectState(name: "Test Project", flavorText: "", goal: [.goods: 100, .data: 200], contributed: contributed, isComplete: false)
    }

    func testRatioIsZeroWithNoContribution() {
        let project = state(contributed: [:])
        XCTAssertEqual(WorldProjectEngine.ratio(project, for: .goods), 0)
    }

    func testRatioClampsAtOneEvenIfOvercontributed() {
        let project = state(contributed: [.goods: 500])
        XCTAssertEqual(WorldProjectEngine.ratio(project, for: .goods), 1)
    }

    func testOverallProgressAveragesAcrossResources() {
        let project = state(contributed: [.goods: 50, .data: 200]) // 0.5 and 1.0
        XCTAssertEqual(WorldProjectEngine.overallProgress(project), 0.75, accuracy: 0.001)
    }

    func testIsCompleteRequiresEveryResourceMet() {
        XCTAssertFalse(WorldProjectEngine.isComplete(state(contributed: [.goods: 100, .data: 199])))
        XCTAssertTrue(WorldProjectEngine.isComplete(state(contributed: [.goods: 100, .data: 200])))
    }

    func testClampedContributionNeverExceedsRemainingGoal() {
        let project = state(contributed: [.goods: 90])
        XCTAssertEqual(WorldProjectEngine.clampedContribution(50, resource: .goods, state: project), 10)
    }

    func testClampedContributionIsZeroForAnUnrelatedResource() {
        let project = state(contributed: [:])
        XCTAssertEqual(WorldProjectEngine.clampedContribution(50, resource: .coins, state: project), 0)
    }
}
