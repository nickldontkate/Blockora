import Foundation

struct PlacementValidation {
    var isValid: Bool
    var reasons: [String]
}

/// The numbers shown in the live placement preview while dragging (§8):
/// "PLACE SERVER MODULE / Data +35/h Energy -18/h / Structure: 82% → 71%".
struct PlacementPreview {
    var isValid: Bool
    var reasons: [String]
    var structuralHealthBefore: Double
    var structuralHealthAfter: Double
    var productionDelta: ResourceBag
}

/// Validates and commits module placement/removal. This is the single place
/// that decides "can this go here" — the SpriteKit drag interaction only asks
/// this engine questions, it never encodes placement rules itself (§43 spirit
/// applied to construction too: logic stays out of the renderer).
enum ConstructionEngine {
    /// Local building grid bounds. Small and fixed for MVP so a plot never
    /// grows into something the camera/UI can't frame (§39/§40 still apply
    /// once districts add more plots — this caps a single building, not the city).
    static let gridBounds = (x: -2...2, y: 0...5)

    static func validatePlacement(
        building: BuildingInstance,
        definition: ModuleDefinition,
        at position: GridPosition,
        playerLevel: Int,
        playerResources: ResourceBag
    ) -> PlacementValidation {
        var reasons: [String] = []

        guard gridBounds.x.contains(position.x), gridBounds.y.contains(position.y) else {
            reasons.append("Outside the buildable plot.")
            return PlacementValidation(isValid: false, reasons: reasons)
        }
        if building.modules[position] != nil {
            reasons.append("Something is already here.")
        }
        if definition.unlockLevel > playerLevel {
            reasons.append("Unlocks at level \(definition.unlockLevel).")
        }
        if !playerResources.canAfford(definition.placementCost) {
            reasons.append("Not enough resources.")
        }
        if definition.isGroundAnchor {
            if position.y != gridBounds.y.lowerBound {
                reasons.append("Foundations must sit on the ground row.")
            }
        } else if building.modules.isEmpty {
            reasons.append("Start with a Foundation.")
        } else {
            let touchesExisting = position.orthogonalNeighbors().values.contains { building.modules[$0] != nil }
            if !touchesExisting {
                reasons.append("Must connect to an existing module.")
            }
        }

        return PlacementValidation(isValid: reasons.isEmpty, reasons: reasons)
    }

    static func preview(
        building: BuildingInstance,
        definition: ModuleDefinition,
        at position: GridPosition,
        playerLevel: Int,
        playerResources: ResourceBag
    ) -> PlacementPreview {
        let validation = validatePlacement(building: building, definition: definition, at: position, playerLevel: playerLevel, playerResources: playerResources)

        let before = evaluateProduction(building: building, playerLevel: playerLevel)
        var hypothetical = building
        var instance = ModuleInstance(definitionID: definition.id, position: position)
        instance.constructionProgress = 1 // preview as if already built
        hypothetical.modules[position] = instance
        let after = evaluateProduction(building: hypothetical, playerLevel: playerLevel)

        var delta: ResourceBag = [:]
        for resource in ResourceType.allCases {
            let d = (after.production.netPerHour[resource] ?? 0) - (before.production.netPerHour[resource] ?? 0)
            if d != 0 { delta[resource] = d }
        }

        return PlacementPreview(
            isValid: validation.isValid,
            reasons: validation.reasons,
            structuralHealthBefore: before.structural.overallHealthPercent,
            structuralHealthAfter: after.structural.overallHealthPercent,
            productionDelta: delta
        )
    }

    /// Commits a validated placement. Callers must have already checked
    /// `validatePlacement` — this does not re-validate, so resource deduction
    /// and level gating stay the caller's (GameSession's) responsibility,
    /// keeping this a pure grid mutation.
    static func place(building: BuildingInstance, definitionID: String, at position: GridPosition) -> BuildingInstance {
        var building = building
        building.modules[position] = ModuleInstance(definitionID: definitionID, position: position)
        return building
    }

    static func remove(building: BuildingInstance, at position: GridPosition) -> BuildingInstance {
        var building = building
        building.modules.removeValue(forKey: position)
        return building
    }

    /// Fraction of a module's original placement cost the "Reinforce" action
    /// (§7) charges — cheaper than tearing it down and rebuilding, which is
    /// the whole point of offering it as an alternative to REDESIGN.
    static let reinforcementCostFactor = 0.4

    static func reinforcementCost(for definition: ModuleDefinition) -> ResourceBag {
        var cost: ResourceBag = [:]
        for (resource, amount) in definition.placementCost {
            cost[resource] = (amount * reinforcementCostFactor).rounded()
        }
        return cost
    }

    /// Runs StructuralEngine and strips any positions it says should collapse,
    /// returning the surviving building and what was lost, for VFX (§7).
    static func resolveCollapse(building: BuildingInstance) -> (building: BuildingInstance, collapsed: Set<GridPosition>) {
        let report = StructuralEngine.evaluate(modules: building.modules)
        guard !report.collapsingPositions.isEmpty else { return (building, []) }
        var updated = building
        for position in report.collapsingPositions {
            updated.modules.removeValue(forKey: position)
        }
        return (updated, report.collapsingPositions)
    }

    private static func evaluateProduction(building: BuildingInstance, playerLevel: Int) -> (structural: StructuralReport, production: ProductionResult) {
        let structural = StructuralEngine.evaluate(modules: building.modules)
        let synergy = SynergyEngine.evaluate(modules: building.modules, playerLevel: playerLevel)
        let production = ProductionEngine.evaluate(building: building, structural: structural, synergy: synergy)
        return (structural, production)
    }
}
