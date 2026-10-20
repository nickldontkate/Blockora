import Foundation

struct ProductionResult {
    /// Net resource change per hour for the whole building, after every multiplier.
    var netPerHour: ResourceBag
    /// 0...1 operating ratio actually achieved per module (1 = full output).
    /// Reduced by energy shortage brownout, data-center heat, or low health.
    var operationalRatio: [GridPosition: Double]
}

/// Combines module base stats with structural connectivity, synergies, events
/// and district bonuses into the resource flow a building actually produces.
///
/// Implements the formula from spec §45:
///   finalProduction = baseModuleProduction × synergyMultiplier × conditionMultiplier
///                      × eventMultiplier × districtMultiplier
/// plus an energy-availability brownout pass (§17/§34): a module that needs
/// power but doesn't have enough of it scales its *entire* output down rather
/// than failing outright, so a struggling building degrades gracefully.
enum ProductionEngine {
    /// Excess heat (heatOutput - coolingCapacity, building-wide) at which Data
    /// Center server output drops to zero.
    static let heatSaturationPoint = 100.0

    static func evaluate(
        building: BuildingInstance,
        structural: StructuralReport,
        synergy: SynergyReport,
        districtModifiers: ResourceBag = [:],
        eventModifiers: ResourceBag = [:]
    ) -> ProductionResult {
        let onlinePositions = building.modules.compactMap { position, instance -> (GridPosition, ModuleInstance, ModuleDefinition)? in
            guard instance.isBuilt,
                  structural.status(at: position)?.isOnline == true,
                  let definition = instance.definition else { return nil }
            return (position, instance, definition)
        }

        // Pass 1: apply synergy + event + district multipliers to each module's
        // *positive* outputs (consumption is a fixed operating cost, not boosted).
        var adjusted: [GridPosition: ResourceBag] = [:]
        for (position, _, definition) in onlinePositions {
            var bag = definition.production
            let synergyMultipliers = synergy.effectsByPosition[position] ?? []
            for (resource, amount) in bag where amount > 0 {
                var multiplier = 1.0
                for effect in synergyMultipliers {
                    if case .productionMultiplier(let effectResource, let factor) = effect, effectResource == resource {
                        multiplier *= factor
                    }
                }
                multiplier *= districtModifiers[resource] ?? 1.0
                multiplier *= eventModifiers[resource] ?? 1.0
                bag[resource] = amount * multiplier
            }
            adjusted[position] = bag
        }

        // Pass 2: energy-availability brownout. Producers are unaffected;
        // consumers that need power scale their whole output by what's available.
        let totalEnergyAvailable = adjusted.values.reduce(0) { $0 + max($1[.energy] ?? 0, 0) }
        let totalEnergyRequested = onlinePositions.reduce(0) { total, entry in
            let (_, _, definition) = entry
            return total + max(-(definition.production[.energy] ?? 0), 0)
        }
        let energyRatio = totalEnergyRequested > 0 ? min(1, totalEnergyAvailable / totalEnergyRequested) : 1

        // Data Center thermal pass: net building heat reduces server efficiency.
        let totalHeat = onlinePositions.reduce(0.0) { $0 + $1.2.heatOutput }
        let totalCooling = onlinePositions.reduce(0.0) { $0 + $1.2.coolingCapacity }
        let netHeat = max(0, totalHeat - totalCooling)
        let heatRatio = max(0, 1 - netHeat / heatSaturationPoint)

        var netPerHour: ResourceBag = [:]
        var operationalRatio: [GridPosition: Double] = [:]

        for (position, instance, definition) in onlinePositions {
            var ratio = instance.health
            if definition.connectionRequirements.contains(.power) && (definition.production[.energy] ?? 0) < 0 {
                ratio *= energyRatio
            }
            if definition.family == .server {
                ratio *= heatRatio
            }
            operationalRatio[position] = ratio

            guard var bag = adjusted[position] else { continue }
            for (resource, amount) in bag {
                bag[resource] = amount * ratio
            }
            netPerHour.add(bag)
        }

        return ProductionResult(netPerHour: netPerHour, operationalRatio: operationalRatio)
    }
}
