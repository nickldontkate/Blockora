import XCTest
@testable import Blockora

final class ProductionEngineTests: XCTestCase {
    private func builtModule(_ definitionID: String, _ x: Int, _ y: Int) -> ModuleInstance {
        ModuleInstance(definitionID: definitionID, position: GridPosition(x: x, y: y), constructionProgress: 1)
    }

    private func evaluate(_ modules: [GridPosition: ModuleInstance], playerLevel: Int = 1) -> ProductionResult {
        let building = BuildingInstance(buildingClass: .farm, plotID: UUID(), displayName: "Test", modules: modules)
        let structural = StructuralEngine.evaluate(modules: modules)
        let synergy = SynergyEngine.evaluate(modules: modules, playerLevel: playerLevel)
        return ProductionEngine.evaluate(building: building, structural: structural, synergy: synergy)
    }

    func testSolarProducesEnergyWhenOnline() {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("solar_panel", 0, 1)

        let result = evaluate(modules)
        XCTAssertEqual(result.netPerHour[.energy] ?? 0, 25, accuracy: 0.01)
    }

    func testEnergyShortageBrownsOutConsumersProportionally() {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("solar_panel", 0, 1) // +25 energy
        modules[GridPosition(x: 1, y: 0)] = builtModule("greenhouse", 1, 0)
        modules[GridPosition(x: -1, y: 0)] = builtModule("greenhouse", -1, 0)
        modules[GridPosition(x: 1, y: 1)] = builtModule("greenhouse", 1, 1)
        modules[GridPosition(x: -1, y: 1)] = builtModule("greenhouse", -1, 1)
        // 4 greenhouses each want -8 energy/h (32 total) against only 25 produced.

        let result = evaluate(modules)
        // Consumption should scale down to match supply rather than going negative.
        XCTAssertEqual(result.netPerHour[.energy] ?? -1, 0, accuracy: 0.05)
        // Food output must be reduced below the unconstrained 4 x 30 = 120/h.
        XCTAssertLessThan(result.netPerHour[.food] ?? 120, 120)
        XCTAssertGreaterThan(result.netPerHour[.food] ?? 0, 0)
    }

    func testSmartIrrigationBoostsFoodOutput() {
        var withoutSynergy: [GridPosition: ModuleInstance] = [:]
        withoutSynergy[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        withoutSynergy[GridPosition(x: 0, y: 1)] = builtModule("solar_panel", 0, 1)
        withoutSynergy[GridPosition(x: 1, y: 0)] = builtModule("greenhouse", 1, 0)
        let baseline = evaluate(withoutSynergy)

        var withSynergy = withoutSynergy
        withSynergy[GridPosition(x: 2, y: 0)] = builtModule("water_tank", 2, 0)
        let boosted = evaluate(withSynergy)

        XCTAssertGreaterThan(boosted.netPerHour[.food] ?? 0, baseline.netPerHour[.food] ?? 0)
    }

    func testDistrictAndEventModifiersBoostMatchingResourceOutput() {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("solar_panel", 0, 1) // produces energy only

        let building = BuildingInstance(buildingClass: .farm, plotID: UUID(), displayName: "Test", modules: modules)
        let structural = StructuralEngine.evaluate(modules: modules)
        let synergy = SynergyEngine.evaluate(modules: modules, playerLevel: 1)
        let baseline = ProductionEngine.evaluate(building: building, structural: structural, synergy: synergy)
        let boosted = ProductionEngine.evaluate(
            building: building, structural: structural, synergy: synergy,
            districtModifiers: [.energy: 1.2], eventModifiers: [.energy: 1.5]
        )

        XCTAssertEqual(boosted.netPerHour[.energy] ?? 0, (baseline.netPerHour[.energy] ?? 0) * 1.2 * 1.5, accuracy: 0.01)
    }

    func testUnbuiltModuleDoesNotProduce() {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = ModuleInstance(definitionID: "solar_panel", position: GridPosition(x: 0, y: 1), constructionProgress: 0.5)

        let result = evaluate(modules)
        XCTAssertEqual(result.netPerHour[.energy] ?? 0, 0, accuracy: 0.001)
    }

    func testDataCenterHeatPenaltyIsReducedByCooling() {
        func dataCenterBuilding(withCooling: Bool) -> BuildingInstance {
            var modules: [GridPosition: ModuleInstance] = [:]
            modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
            modules[GridPosition(x: 0, y: 1)] = builtModule("structural_core", 0, 1)
            modules[GridPosition(x: 1, y: 1)] = builtModule("server_rack", 1, 1)
            modules[GridPosition(x: 0, y: 2)] = builtModule("solar_panel", 0, 2)
            if withCooling {
                modules[GridPosition(x: -1, y: 1)] = builtModule("cooling_unit", -1, 1)
            }
            return BuildingInstance(buildingClass: .dataCenter, plotID: UUID(), displayName: "DC", modules: modules)
        }

        func dataOutput(withCooling: Bool) -> Double {
            let building = dataCenterBuilding(withCooling: withCooling)
            let structural = StructuralEngine.evaluate(modules: building.modules)
            let synergy = SynergyEngine.evaluate(modules: building.modules, playerLevel: 5)
            return ProductionEngine.evaluate(building: building, structural: structural, synergy: synergy).netPerHour[.data] ?? 0
        }

        XCTAssertGreaterThan(dataOutput(withCooling: true), dataOutput(withCooling: false))
    }
}
