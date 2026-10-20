import Foundation

/// A saved building layout a player can reuse (§28) or later share/remix (§30,
/// not implemented in MVP). Saving a blueprint stores the *layout*; placing it
/// still consumes real resources/modules — it is not a shortcut around cost.
struct Blueprint: Identifiable, Codable {
    let id: UUID
    var name: String
    var buildingClass: BuildingClass
    var moduleDefinitionIDs: [GridPosition: String]
    var createdAt: Date

    /// Cached summary shown in the codex without re-running the engines.
    var summary: BlueprintSummary
}

struct BlueprintSummary: Codable {
    var efficiencyPercent: Double
    var netProduction: ResourceBag
    var stabilityPercent: Double
    var synergyCount: Int
}

/// A discoverable module combination (§5). Definitions are data so new synergies
/// are additions here, not new SynergyEngine branches (§44).
struct SynergyDefinition: Identifiable, Codable {
    let id: String
    let displayName: String
    let flavorText: String
    let pattern: SynergyPattern
    let effect: SynergyEffect
    let unlockLevel: Int
}

enum SynergyPattern: Codable {
    /// Two specific families adjacent anywhere in the building.
    case adjacentPair(ModuleFamily, ModuleFamily)
    /// N-or-more modules of the same family mutually adjacent (a cluster).
    case adjacentCluster(ModuleFamily, minCount: Int)
    /// `count` modules of `family` orthogonally surrounding a Structural Core.
    case surroundingCore(ModuleFamily, count: Int)
}

enum SynergyEffect: Codable {
    /// Multiplies the named resource's production for every participating module.
    case productionMultiplier(resource: ResourceType, multiplier: Double)
}
