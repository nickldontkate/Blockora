import XCTest
@testable import Blockora

final class PlotExpansionEngineTests: XCTestCase {
    private func plot(x: Int, unlocked: Bool, cost: Double?) -> Plot {
        Plot(
            id: UUID(), districtID: UUID(), worldPosition: GridPosition(x: x, y: 0),
            buildingID: nil, isUnlocked: unlocked,
            unlockCost: cost.map { [.coins: $0] } ?? [:]
        )
    }

    func testDoesNotExpandWhileAnyPlotIsStillLocked() {
        let plots = [plot(x: 0, unlocked: true, cost: nil), plot(x: 1, unlocked: false, cost: 800)]
        XCTAssertFalse(PlotExpansionEngine.shouldExpand(districtPlots: plots, maxPlots: 6))
    }

    func testExpandsOnceEveryPlotIsUnlocked() {
        let plots = [plot(x: 0, unlocked: true, cost: nil), plot(x: 1, unlocked: true, cost: 800)]
        XCTAssertTrue(PlotExpansionEngine.shouldExpand(districtPlots: plots, maxPlots: 6))
    }

    func testStopsExpandingAtTheCap() {
        let plots = (0..<6).map { plot(x: $0, unlocked: true, cost: 800) }
        XCTAssertFalse(PlotExpansionEngine.shouldExpand(districtPlots: plots, maxPlots: 6))
    }

    func testNextCostScalesFromTheMostExpensiveExistingPlot() {
        let plots = [plot(x: 0, unlocked: true, cost: nil), plot(x: 1, unlocked: true, cost: 800), plot(x: 2, unlocked: true, cost: 2200)]
        let next = PlotExpansionEngine.nextUnlockCost(districtPlots: plots)
        XCTAssertEqual(next, 4000, accuracy: 0.01) // 2200 * 1.8 = 3960, rounded to nearest 100
    }

    func testNextWorldPositionContinuesThePlotRow() {
        let plots = [plot(x: 0, unlocked: true, cost: nil), plot(x: 2, unlocked: true, cost: 2200)]
        XCTAssertEqual(PlotExpansionEngine.nextWorldPosition(districtPlots: plots), GridPosition(x: 3, y: 0))
    }
}
