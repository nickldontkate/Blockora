import Foundation

struct OfflineSimulationResult {
    var elapsedSeconds: TimeInterval
    var wasCapped: Bool
    /// Final amount minus starting amount, per resource — what the "While You
    /// Were Away" summary shows (§35).
    var resourceDeltas: ResourceBag
    var updatedResources: ResourceBag
}

/// Server-authoritative-shaped offline production (§34). The client runs this
/// same pure function locally today (LocalEconomyService) and will eventually
/// call the Cloudflare equivalent instead — the *math* doesn't change, only
/// who's trusted to run it.
///
/// Deliberately closed-form rather than a tick loop: because a building's
/// online/synergy state can't change while the player is away (no input is
/// possible), each resource's net rate is constant for the whole window, so
/// its trajectory (grow to cap, or drain to zero and stop) can be solved
/// directly. This keeps the engine fast, deterministic and easy to unit test
/// while still respecting storage caps and "ran out partway through" (§34) —
/// it does not just multiply incomePerHour × hours.
enum OfflineSimulationEngine {
    static let maxOfflineDuration: TimeInterval = 8 * 3600

    static func simulate(
        resources: ResourceBag,
        storageCapacity: ResourceBag,
        buildings: [BuildingInstance],
        playerLevel: Int,
        elapsedSince lastSync: Date,
        now: Date
    ) -> OfflineSimulationResult {
        let rawElapsed = max(0, now.timeIntervalSince(lastSync))
        let elapsed = min(rawElapsed, maxOfflineDuration)
        let hours = elapsed / 3600

        var ratePerHour: ResourceBag = [:]
        for building in buildings {
            let structural = StructuralEngine.evaluate(modules: building.modules)
            let synergy = SynergyEngine.evaluate(modules: building.modules, playerLevel: playerLevel)
            let production = ProductionEngine.evaluate(building: building, structural: structural, synergy: synergy)
            ratePerHour.add(production.netPerHour)
        }

        var finalResources = resources
        for (resource, rate) in ratePerHour {
            let start = resources[resource, default: 0]
            let cap = storageCapacity[resource]
            finalResources[resource] = projectedAmount(start: start, ratePerHour: rate, hours: hours, cap: cap)
        }

        var deltas: ResourceBag = [:]
        for resource in ResourceType.allCases {
            let delta = finalResources[resource, default: 0] - resources[resource, default: 0]
            if delta != 0 { deltas[resource] = delta }
        }

        return OfflineSimulationResult(
            elapsedSeconds: elapsed,
            wasCapped: rawElapsed > maxOfflineDuration,
            resourceDeltas: deltas,
            updatedResources: finalResources
        )
    }

    /// Solves a constant-rate trajectory over `hours`, stopping at zero if it's
    /// draining or at `cap` if it's filling (excess production beyond a full
    /// storage is lost, matching typical offline-production expectations).
    private static func projectedAmount(start: Double, ratePerHour: Double, hours: Double, cap: Double?) -> Double {
        guard ratePerHour != 0, hours > 0 else { return start }
        if ratePerHour > 0 {
            let unclamped = start + ratePerHour * hours
            return cap.map { min(unclamped, $0) } ?? unclamped
        } else {
            let timeToZero = start / -ratePerHour
            if timeToZero >= hours {
                return start + ratePerHour * hours
            }
            return 0
        }
    }
}
