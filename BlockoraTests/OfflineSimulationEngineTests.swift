import XCTest
@testable import Blockora

final class OfflineSimulationEngineTests: XCTestCase {
    private func farmBuilding() -> BuildingInstance {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = ModuleInstance(definitionID: "foundation_basic", position: GridPosition(x: 0, y: 0), constructionProgress: 1)
        modules[GridPosition(x: 0, y: 1)] = ModuleInstance(definitionID: "farm_field", position: GridPosition(x: 0, y: 1), constructionProgress: 1) // +18 food/h, no connection requirement
        return BuildingInstance(buildingClass: .farm, plotID: UUID(), displayName: "Farm", modules: modules)
    }

    func testProductionAccruesAcrossElapsedTime() {
        let now = Date()
        let result = OfflineSimulationEngine.simulate(
            resources: [:], storageCapacity: [.food: 1000],
            buildings: [farmBuilding()], playerLevel: 1,
            elapsedSince: now.addingTimeInterval(-3600), now: now
        )
        XCTAssertEqual(result.resourceDeltas[.food] ?? 0, 18, accuracy: 0.01)
        XCTAssertFalse(result.wasCapped)
    }

    func testOfflineDurationIsCappedAtEightHours() {
        let now = Date()
        let result = OfflineSimulationEngine.simulate(
            resources: [:], storageCapacity: [.food: 10_000],
            buildings: [farmBuilding()], playerLevel: 1,
            elapsedSince: now.addingTimeInterval(-20 * 3600), now: now
        )
        XCTAssertTrue(result.wasCapped)
        XCTAssertEqual(result.elapsedSeconds, 8 * 3600, accuracy: 1)
        XCTAssertEqual(result.resourceDeltas[.food] ?? 0, 18 * 8, accuracy: 0.01)
    }

    func testProductionStopsAtStorageCap() {
        let now = Date()
        let result = OfflineSimulationEngine.simulate(
            resources: [.food: 90], storageCapacity: [.food: 100],
            buildings: [farmBuilding()], playerLevel: 1,
            elapsedSince: now.addingTimeInterval(-3600), now: now
        )
        // 90 + 18 would be 108, but storage caps at 100.
        XCTAssertEqual(result.updatedResources[.food] ?? 0, 100, accuracy: 0.01)
    }

    func testConsumptionNeverDrainsBelowZero() {
        // A processing unit (-10 food/h) with only 3 food banked should run out
        // partway through the hour and stop at zero, not go negative.
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = ModuleInstance(definitionID: "foundation_basic", position: GridPosition(x: 0, y: 0), constructionProgress: 1)
        modules[GridPosition(x: 0, y: 1)] = ModuleInstance(definitionID: "structural_core", position: GridPosition(x: 0, y: 1), constructionProgress: 1)
        modules[GridPosition(x: 1, y: 1)] = ModuleInstance(definitionID: "processing_unit", position: GridPosition(x: 1, y: 1), constructionProgress: 1)
        let building = BuildingInstance(buildingClass: .farm, plotID: UUID(), displayName: "Farm", modules: modules)

        let now = Date()
        let result = OfflineSimulationEngine.simulate(
            resources: [.food: 3], storageCapacity: [.food: 1000],
            buildings: [building], playerLevel: 1,
            elapsedSince: now.addingTimeInterval(-3600), now: now
        )
        XCTAssertEqual(result.updatedResources[.food] ?? -1, 0, accuracy: 0.01)
    }
}
