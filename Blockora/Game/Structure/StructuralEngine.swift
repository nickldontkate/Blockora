import Foundation

/// Per-module result of a structural evaluation (§6/§7).
struct StructuralModuleStatus: Equatable {
    var isGrounded: Bool
    var load: Double
    var capacity: Double
    var stressRatio: Double
    var connectionState: ConnectionState
    var hasPowerConnection: Bool
    var hasCoreConnection: Bool
    /// True once construction is complete, grounded, and every connection
    /// requirement the module declares is satisfied.
    var isOnline: Bool
    /// True if this module should be removed this evaluation — either it lost
    /// all support (§7 localized collapse) or its stress passed the hard
    /// failure threshold, taking its supported subtree with it.
    var shouldCollapse: Bool
}

struct StructuralReport {
    var statuses: [GridPosition: StructuralModuleStatus]
    var overallHealthPercent: Double
    /// Every position that should be removed as a result of this evaluation.
    /// Deliberately scoped to the failed module's own supported subtree, never
    /// the whole building (§7).
    var collapsingPositions: Set<GridPosition>

    func status(at position: GridPosition) -> StructuralModuleStatus? { statuses[position] }
}

/// Computes structural load, support and connectivity for a building's module
/// grid. Pure, deterministic, and independent of rendering — see design note
/// in spec §43: "simplified approach is acceptable... must be deterministic,
/// testable, fast, understandable."
///
/// Algorithm: BFS from every ground-anchored module builds a support spanning
/// tree over orthogonal neighbors (ties broken by grid scan order, so the same
/// input always produces the same tree). Load on a module is its own weight
/// plus the load of every tree-descendant; stress is load ÷ that module's
/// support capacity.
enum StructuralEngine {
    static let warningThreshold = 0.75
    static let dangerThreshold = 1.0
    /// Stress ratio at which a module's supported subtree fails outright.
    static let failureThreshold = 1.35
    /// Support-capacity boost from the paid "Reinforce" action (§7).
    static let reinforcementMultiplier = 1.5

    static func evaluate(modules: [GridPosition: ModuleInstance]) -> StructuralReport {
        var definitions: [GridPosition: ModuleDefinition] = [:]
        for (position, instance) in modules {
            guard instance.isBuilt, let definition = instance.definition else { continue }
            definitions[position] = definition
        }

        let (order, parent, children) = buildSupportTree(definitions: definitions)
        let visited = Set(order)

        var load: [GridPosition: Double] = [:]
        for position in order.reversed() {
            let ownWeight = definitions[position]?.weight ?? 0
            let childLoad = (children[position] ?? []).reduce(0) { $0 + (load[$1] ?? 0) }
            load[position] = ownWeight + childLoad
        }

        let physicalComponents = connectedComponents(definitions: definitions)
        let powerSourceComponents = Set(
            physicalComponents.filter { component in
                component.contains { position in (definitions[position]?.production[.energy] ?? 0) > 0 }
            }.flatMap { $0 }
        )

        var statuses: [GridPosition: StructuralModuleStatus] = [:]
        var failedRoots: Set<GridPosition> = []

        for (position, definition) in definitions {
            let grounded = visited.contains(position)
            let load = load[position] ?? definition.weight
            let reinforced = modules[position]?.isReinforced ?? false
            let capacity = max(definition.support * (reinforced ? reinforcementMultiplier : 1.0), 0.0001)
            let ratio = load / capacity

            let connectionState: ConnectionState
            if !grounded || ratio > dangerThreshold {
                connectionState = .danger
            } else if ratio > warningThreshold {
                connectionState = .warning
            } else {
                connectionState = .safe
            }

            let hasCore = definition.family == .structuralCore
                || position.orthogonalNeighbors().values.contains { definitions[$0]?.family == .structuralCore }
            let hasPower = definition.production[.energy].map { $0 > 0 } ?? false
                || powerSourceComponents.contains(position)

            let needsPower = definition.connectionRequirements.contains(.power)
            let needsCore = definition.connectionRequirements.contains(.core)
            let isOnline = grounded && (!needsPower || hasPower) && (!needsCore || hasCore)

            let shouldFail = !grounded || ratio > failureThreshold
            if shouldFail { failedRoots.insert(position) }

            statuses[position] = StructuralModuleStatus(
                isGrounded: grounded,
                load: load,
                capacity: capacity,
                stressRatio: ratio,
                connectionState: connectionState,
                hasPowerConnection: hasPower,
                hasCoreConnection: hasCore,
                isOnline: isOnline,
                shouldCollapse: shouldFail
            )
        }

        // A failure takes its supported subtree with it — never the whole building.
        var collapsing = failedRoots
        var stack = Array(failedRoots)
        while let position = stack.popLast() {
            for child in children[position] ?? [] where !collapsing.contains(child) {
                collapsing.insert(child)
                stack.append(child)
            }
        }

        let stableCount = statuses.values.filter { $0.connectionState != .danger }.count
        let overallHealth = statuses.isEmpty ? 1.0 : Double(stableCount) / Double(statuses.count)

        return StructuralReport(statuses: statuses, overallHealthPercent: overallHealth, collapsingPositions: collapsing)
    }

    /// BFS from every ground anchor. Returns visitation order (for bottom-up load
    /// accumulation), each node's tree parent, and each node's tree children.
    private static func buildSupportTree(
        definitions: [GridPosition: ModuleDefinition]
    ) -> (order: [GridPosition], parent: [GridPosition: GridPosition], children: [GridPosition: [GridPosition]]) {
        let seeds = definitions.filter { $0.value.isGroundAnchor }.keys.sorted()
        var visited = Set<GridPosition>()
        var parent: [GridPosition: GridPosition] = [:]
        var queue: [GridPosition] = []
        var order: [GridPosition] = []

        for seed in seeds where visited.insert(seed).inserted {
            queue.append(seed)
            order.append(seed)
        }

        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for direction in GridDirection.allCases {
                guard let neighbor = current.orthogonalNeighbors()[direction],
                      definitions[neighbor] != nil,
                      !visited.contains(neighbor) else { continue }
                visited.insert(neighbor)
                parent[neighbor] = current
                queue.append(neighbor)
                order.append(neighbor)
            }
        }

        var children: [GridPosition: [GridPosition]] = [:]
        for (child, node) in parent {
            children[node, default: []].append(child)
        }
        return (order, parent, children)
    }

    /// Connected components over *physical* adjacency (regardless of ground
    /// support) — this is the wiring graph power flows through.
    private static func connectedComponents(definitions: [GridPosition: ModuleDefinition]) -> [Set<GridPosition>] {
        var remaining = Set(definitions.keys)
        var components: [Set<GridPosition>] = []
        while let start = remaining.first {
            var component: Set<GridPosition> = []
            var stack = [start]
            while let position = stack.popLast() {
                guard remaining.contains(position) else { continue }
                remaining.remove(position)
                component.insert(position)
                for neighbor in position.orthogonalNeighbors().values where definitions[neighbor] != nil {
                    stack.append(neighbor)
                }
            }
            components.append(component)
        }
        return components
    }
}
