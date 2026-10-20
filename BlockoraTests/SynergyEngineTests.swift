import XCTest
@testable import Blockora

final class SynergyEngineTests: XCTestCase {
    private func builtModule(_ definitionID: String, _ x: Int, _ y: Int) -> ModuleInstance {
        ModuleInstance(definitionID: definitionID, position: GridPosition(x: x, y: y), constructionProgress: 1)
    }

    func testGreenhouseAndWaterTankDiscoverSmartIrrigation() {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("greenhouse", 0, 1)
        modules[GridPosition(x: 1, y: 1)] = builtModule("water_tank", 1, 1)

        let report = SynergyEngine.evaluate(modules: modules, playerLevel: 1)
        XCTAssertTrue(report.discoveredDefinitionIDs.contains("smart_irrigation"))
        XCTAssertNotNil(report.effectsByPosition[GridPosition(x: 0, y: 1)])
    }

    func testNoSynergyWithoutAdjacency() {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("greenhouse", 0, 1)
        modules[GridPosition(x: 3, y: 3)] = builtModule("water_tank", 3, 3) // far away, not adjacent

        let report = SynergyEngine.evaluate(modules: modules, playerLevel: 1)
        XCTAssertFalse(report.discoveredDefinitionIDs.contains("smart_irrigation"))
    }

    func testSynergyLockedUntilPlayerLevel() {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("server_rack", 0, 1)
        modules[GridPosition(x: 1, y: 1)] = builtModule("server_rack", 1, 1)

        // data_cluster unlocks at level 4 — below that it must not fire even
        // though the physical pattern matches.
        let lowLevelReport = SynergyEngine.evaluate(modules: modules, playerLevel: 1)
        XCTAssertFalse(lowLevelReport.discoveredDefinitionIDs.contains("data_cluster"))

        let unlockedReport = SynergyEngine.evaluate(modules: modules, playerLevel: 4)
        XCTAssertTrue(unlockedReport.discoveredDefinitionIDs.contains("data_cluster"))
    }

    func testFourServersSurroundingCoreDiscoverServerMatrix() {
        var modules: [GridPosition: ModuleInstance] = [:]
        let core = GridPosition(x: 0, y: 0)
        modules[core] = builtModule("structural_core", 0, 0)
        for neighbor in core.orthogonalNeighbors().values {
            modules[neighbor] = builtModule("server_rack", neighbor.x, neighbor.y)
        }

        let report = SynergyEngine.evaluate(modules: modules, playerLevel: 5)
        XCTAssertTrue(report.discoveredDefinitionIDs.contains("server_matrix"))
    }
}
