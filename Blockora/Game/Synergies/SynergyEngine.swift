import Foundation

/// One instance of a matched pattern in the current grid — e.g. a specific
/// greenhouse+tank pair, or a specific 4-server ring around a specific core.
struct SynergyOccurrence: Identifiable {
    var id: String { "\(definitionID)-\(positions.sorted().map { "\($0.x).\($0.y)" }.joined(separator: "_"))" }
    let definitionID: String
    let positions: Set<GridPosition>
}

struct SynergyReport {
    var occurrences: [SynergyOccurrence]
    /// Effects active at each position, ready for ProductionEngine to apply.
    var effectsByPosition: [GridPosition: [SynergyEffect]]
    var discoveredDefinitionIDs: Set<String> { Set(occurrences.map(\.definitionID)) }
}

/// Matches SynergyCodex patterns against a building's current, *built* modules.
/// Purely combinatorial — no randomness, no hidden state — so the same layout
/// always yields the same synergies (§44).
enum SynergyEngine {
    static func evaluate(modules: [GridPosition: ModuleInstance], playerLevel: Int) -> SynergyReport {
        var families: [GridPosition: ModuleFamily] = [:]
        for (position, instance) in modules {
            guard instance.isBuilt, let family = instance.definition?.family else { continue }
            families[position] = family
        }

        var occurrences: [SynergyOccurrence] = []
        for definition in SynergyCodex.all where definition.unlockLevel <= playerLevel {
            occurrences.append(contentsOf: match(definition: definition, families: families))
        }

        var effectsByPosition: [GridPosition: [SynergyEffect]] = [:]
        for occurrence in occurrences {
            guard let definition = SynergyCodex.definition(for: occurrence.definitionID) else { continue }
            for position in occurrence.positions {
                effectsByPosition[position, default: []].append(definition.effect)
            }
        }

        return SynergyReport(occurrences: occurrences, effectsByPosition: effectsByPosition)
    }

    private static func match(definition: SynergyDefinition, families: [GridPosition: ModuleFamily]) -> [SynergyOccurrence] {
        switch definition.pattern {
        case .adjacentPair(let a, let b):
            return matchAdjacentPair(definitionID: definition.id, a, b, families: families)
        case .adjacentCluster(let family, let minCount):
            return matchAdjacentCluster(definitionID: definition.id, family, minCount: minCount, families: families)
        case .surroundingCore(let family, let count):
            return matchSurroundingCore(definitionID: definition.id, family, count: count, families: families)
        }
    }

    private static func matchAdjacentPair(
        definitionID: String, _ a: ModuleFamily, _ b: ModuleFamily, families: [GridPosition: ModuleFamily]
    ) -> [SynergyOccurrence] {
        var seenPairs: Set<Set<GridPosition>> = []
        var occurrences: [SynergyOccurrence] = []
        for (position, family) in families.sorted(by: { $0.key < $1.key }) where family == a {
            for neighbor in position.orthogonalNeighbors().values where families[neighbor] == b {
                let pair: Set<GridPosition> = [position, neighbor]
                guard seenPairs.insert(pair).inserted else { continue }
                occurrences.append(SynergyOccurrence(definitionID: definitionID, positions: pair))
            }
        }
        return occurrences
    }

    private static func matchAdjacentCluster(
        definitionID: String, _ family: ModuleFamily, minCount: Int, families: [GridPosition: ModuleFamily]
    ) -> [SynergyOccurrence] {
        let candidates = Set(families.filter { $0.value == family }.keys)
        var remaining = candidates
        var occurrences: [SynergyOccurrence] = []
        while let start = remaining.sorted().first {
            var component: Set<GridPosition> = []
            var stack = [start]
            while let position = stack.popLast() {
                guard remaining.contains(position) else { continue }
                remaining.remove(position)
                component.insert(position)
                for neighbor in position.orthogonalNeighbors().values where candidates.contains(neighbor) {
                    stack.append(neighbor)
                }
            }
            if component.count >= minCount {
                occurrences.append(SynergyOccurrence(definitionID: definitionID, positions: component))
            }
        }
        return occurrences
    }

    private static func matchSurroundingCore(
        definitionID: String, _ family: ModuleFamily, count: Int, families: [GridPosition: ModuleFamily]
    ) -> [SynergyOccurrence] {
        var occurrences: [SynergyOccurrence] = []
        for (position, coreFamily) in families.sorted(by: { $0.key < $1.key }) where coreFamily == .structuralCore {
            let matchingNeighbors = position.orthogonalNeighbors().values.filter { families[$0] == family }
            if matchingNeighbors.count >= count {
                occurrences.append(SynergyOccurrence(definitionID: definitionID, positions: Set(matchingNeighbors).union([position])))
            }
        }
        return occurrences
    }
}
