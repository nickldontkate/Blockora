import Foundation

/// A player-designed building sitting on a plot. `modules` is the authoritative
/// grid state every engine reads; there is no separate "visual layout" — what's
/// in this dictionary is what gets rendered and what produces resources.
struct BuildingInstance: Identifiable, Codable {
    let id: UUID
    var buildingClass: BuildingClass
    var plotID: UUID
    var displayName: String
    var modules: [GridPosition: ModuleInstance]

    init(
        id: UUID = UUID(),
        buildingClass: BuildingClass,
        plotID: UUID,
        displayName: String,
        modules: [GridPosition: ModuleInstance] = [:]
    ) {
        self.id = id
        self.buildingClass = buildingClass
        self.plotID = plotID
        self.displayName = displayName
        self.modules = modules
    }

    var footprint: (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let xs = modules.keys.map(\.x)
        let ys = modules.keys.map(\.y)
        return (xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0)
    }

    var isEmpty: Bool { modules.isEmpty }

    func module(at position: GridPosition) -> ModuleInstance? { modules[position] }
}

/// A buildable plot in the world. Empty plots show construction affordances
/// in-world (§15) rather than as a menu entry.
struct Plot: Identifiable, Codable {
    let id: UUID
    var districtID: UUID
    /// World-space grid coordinate on the island (not the building's internal grid).
    var worldPosition: GridPosition
    var buildingID: UUID?
    var isUnlocked: Bool
    var unlockCost: ResourceBag

    var isBuildable: Bool { isUnlocked && buildingID == nil }
}

struct District: Identifiable, Codable {
    let id: UUID
    var name: String
    var isUnlocked: Bool
    /// Multiplicative production bonus/penalty per resource for buildings sited here (§24/§25).
    var productionModifiers: ResourceBag
    var plotIDs: [UUID]
}
