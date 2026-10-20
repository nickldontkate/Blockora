import Foundation

/// The full, data-driven synergy list (§5/§44). Adding a new combo means adding
/// an entry here — SynergyEngine's matching code never changes.
enum SynergyCodex {
    static let all: [SynergyDefinition] = [
        SynergyDefinition(
            id: "smart_irrigation",
            displayName: "Smart Irrigation",
            flavorText: "A greenhouse fed straight from the tank never runs dry.",
            pattern: .adjacentPair(.greenhouse, .waterTank),
            effect: .productionMultiplier(resource: .food, multiplier: 1.20),
            unlockLevel: 1
        ),
        SynergyDefinition(
            id: "data_cluster",
            displayName: "Data Cluster",
            flavorText: "Two racks sharing a backbone push more data than either alone.",
            pattern: .adjacentCluster(.server, minCount: 2),
            effect: .productionMultiplier(resource: .data, multiplier: 1.10),
            unlockLevel: 4
        ),
        SynergyDefinition(
            id: "server_matrix",
            displayName: "Server Matrix",
            flavorText: "Four racks ringing a core, all load-balanced through it.",
            pattern: .surroundingCore(.server, count: 4),
            effect: .productionMultiplier(resource: .data, multiplier: 1.25),
            unlockLevel: 4
        ),
    ]

    static func definition(for id: String) -> SynergyDefinition? {
        all.first { $0.id == id }
    }

    /// UI copy for the codex (§5): obfuscated until discovered, revealed after.
    static func codexLine(for definition: SynergyDefinition, discovered: Bool) -> String {
        guard discovered else { return "??? + ??? = ???" }
        switch definition.effect {
        case .productionMultiplier(let resource, let multiplier):
            let bonus = Int((multiplier - 1) * 100)
            return "\(definition.displayName) — \(resource.displayName) +\(bonus)%"
        }
    }
}
