import XCTest
@testable import Blockora

final class StructuralEngineTests: XCTestCase {
    private func builtModule(_ definitionID: String, _ x: Int, _ y: Int) -> ModuleInstance {
        ModuleInstance(definitionID: definitionID, position: GridPosition(x: x, y: y), constructionProgress: 1)
    }

    func testFoundationIsGrounded() {
        let modules = [GridPosition(x: 0, y: 0): builtModule("foundation_basic", 0, 0)]
        let report = StructuralEngine.evaluate(modules: modules)
        XCTAssertTrue(report.status(at: GridPosition(x: 0, y: 0))!.isGrounded)
        XCTAssertEqual(report.status(at: GridPosition(x: 0, y: 0))!.connectionState, .safe)
    }

    func testDisconnectedModuleIsUngroundedAndDangerous() {
        // A core floating with no foundation beneath it should never register as grounded.
        let modules = [GridPosition(x: 0, y: 3): builtModule("structural_core", 0, 3)]
        let report = StructuralEngine.evaluate(modules: modules)
        let status = report.status(at: GridPosition(x: 0, y: 3))!
        XCTAssertFalse(status.isGrounded)
        XCTAssertEqual(status.connectionState, .danger)
        XCTAssertTrue(report.collapsingPositions.contains(GridPosition(x: 0, y: 3)))
    }

    func testLoadPropagatesThroughSupportTree() {
        // foundation -> core (weight 6) -> storage (weight 8) stacked upward.
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("structural_core", 0, 1)
        modules[GridPosition(x: 0, y: 2)] = builtModule("storage_crate", 0, 2)

        let report = StructuralEngine.evaluate(modules: modules)
        let coreStatus = report.status(at: GridPosition(x: 0, y: 1))!
        // Core carries its own weight (6) plus the storage module's weight (8) above it.
        XCTAssertEqual(coreStatus.load, 14, accuracy: 0.001)
        XCTAssertTrue(coreStatus.isGrounded)
    }

    func testLocalizedCollapseOnlyRemovesOverloadedSubtree() {
        // A wildly overloaded module should take only what it supports with it,
        // never a sibling branch grounded independently through the foundation,
        // and never a stable ancestor further down the same tree.
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: -1, y: 0)] = builtModule("foundation_basic", -1, 0)
        modules[GridPosition(x: -1, y: 1)] = builtModule("storage_crate", -1, 1) // independent branch, should survive

        // Core stays under its failure threshold; the generator directly above
        // it (support capacity 6) is crushed by two more generators stacked on it.
        modules[GridPosition(x: 0, y: 1)] = builtModule("structural_core", 0, 1)
        modules[GridPosition(x: 0, y: 2)] = builtModule("power_generator", 0, 2)
        modules[GridPosition(x: 0, y: 3)] = builtModule("power_generator", 0, 3)
        modules[GridPosition(x: 0, y: 4)] = builtModule("power_generator", 0, 4)

        let report = StructuralEngine.evaluate(modules: modules)
        XCTAssertTrue(report.collapsingPositions.contains(GridPosition(x: 0, y: 2)))
        XCTAssertTrue(report.collapsingPositions.contains(GridPosition(x: 0, y: 3)))
        XCTAssertTrue(report.collapsingPositions.contains(GridPosition(x: 0, y: 4)))
        XCTAssertFalse(report.collapsingPositions.contains(GridPosition(x: 0, y: 1)), "The core underneath must stay under its own failure threshold")
        XCTAssertFalse(report.collapsingPositions.contains(GridPosition(x: 0, y: 0)), "Foundation never collapses")
        XCTAssertFalse(report.collapsingPositions.contains(GridPosition(x: -1, y: 1)), "Independent branch must survive a failure elsewhere")
    }

    func testReinforcementRaisesEffectiveSupportCapacity() {
        // Three generators on a core overloads it (see the localized-collapse
        // test above); reinforcing the core should let it carry the same load.
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("structural_core", 0, 1)
        modules[GridPosition(x: 0, y: 2)] = builtModule("power_generator", 0, 2)
        modules[GridPosition(x: 0, y: 3)] = builtModule("power_generator", 0, 3)

        let before = StructuralEngine.evaluate(modules: modules)
        let coreBefore = before.status(at: GridPosition(x: 0, y: 1))!

        modules[GridPosition(x: 0, y: 1)]?.isReinforced = true
        let after = StructuralEngine.evaluate(modules: modules)
        let coreAfter = after.status(at: GridPosition(x: 0, y: 1))!

        XCTAssertEqual(coreAfter.capacity, coreBefore.capacity * StructuralEngine.reinforcementMultiplier, accuracy: 0.001)
        XCTAssertLessThan(coreAfter.stressRatio, coreBefore.stressRatio)
    }

    func testServerRequiresPowerAndCoreToComeOnline() {
        var modules: [GridPosition: ModuleInstance] = [:]
        modules[GridPosition(x: 0, y: 0)] = builtModule("foundation_basic", 0, 0)
        modules[GridPosition(x: 0, y: 1)] = builtModule("server_rack", 0, 1) // no core, no power neighbor

        let report = StructuralEngine.evaluate(modules: modules)
        XCTAssertFalse(report.status(at: GridPosition(x: 0, y: 1))!.isOnline)

        modules[GridPosition(x: 1, y: 1)] = builtModule("structural_core", 1, 1)
        modules[GridPosition(x: 0, y: 2)] = builtModule("solar_panel", 0, 2)
        let poweredReport = StructuralEngine.evaluate(modules: modules)
        XCTAssertTrue(poweredReport.status(at: GridPosition(x: 0, y: 1))!.isOnline)
    }
}
