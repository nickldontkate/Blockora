import Foundation

/// Persistent progress toward the shared global build (§31). Until the city
/// connects to the Blockora servers (§59: no fake production values) this
/// tracks only the *local* player's own contribution, honestly labeled as
/// such in the UI — not an invented shared total.
struct WorldProjectState: Codable {
    var name: String
    var flavorText: String
    var goal: ResourceBag
    var contributed: ResourceBag
    var isComplete: Bool

    static func skybridge() -> WorldProjectState {
        WorldProjectState(
            name: "Blockora Skybridge",
            flavorText: "A cross-island span every builder is chipping in on.",
            goal: [.goods: 2000, .data: 1500, .energy: 1000],
            contributed: [:],
            isComplete: false
        )
    }
}

/// Pure progress math over a `WorldProjectState` — no I/O, no randomness.
enum WorldProjectEngine {
    static func ratio(_ state: WorldProjectState, for resource: ResourceType) -> Double {
        guard let goalAmount = state.goal[resource], goalAmount > 0 else { return 1 }
        return min(1, (state.contributed[resource] ?? 0) / goalAmount)
    }

    /// Overall completion across every required resource, evenly weighted.
    static func overallProgress(_ state: WorldProjectState) -> Double {
        let resources = Array(state.goal.keys)
        guard !resources.isEmpty else { return 0 }
        return resources.reduce(0) { $0 + ratio(state, for: $1) } / Double(resources.count)
    }

    static func isComplete(_ state: WorldProjectState) -> Bool {
        state.goal.allSatisfy { resource, amount in (state.contributed[resource] ?? 0) >= amount }
    }

    /// Clamps a contribution so `contributed` never exceeds `goal` for that
    /// resource (excess would just be an invisible, meaningless surplus).
    static func clampedContribution(_ amount: Double, resource: ResourceType, state: WorldProjectState) -> Double {
        guard let goalAmount = state.goal[resource] else { return 0 }
        let remaining = max(0, goalAmount - (state.contributed[resource] ?? 0))
        return min(amount, remaining)
    }

    /// One-time reward for finishing the project — a milestone payout, not a
    /// recurring income stream (§31 treats this as a landmark, not a farm).
    static func completionReward() -> ResourceBag {
        [.coins: 5000, .blocks: 100]
    }
}
