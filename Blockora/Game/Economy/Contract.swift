import Foundation

/// A server-generated (in MVP: locally generated, same shape) request the city
/// can fulfil for a reward (§22). Renamed internally from "trading" to
/// "demand fulfilment" per §21 — the player supplies, they don't speculate.
struct Contract: Identifiable, Codable {
    let id: UUID
    var title: String
    var flavorText: String
    var requiredResources: ResourceBag
    var rewardResources: ResourceBag
    var rewardExperience: Double
    var duration: TimeInterval
    var status: ContractStatus
    var acceptedAt: Date?

    func isExpired(now: Date) -> Bool {
        guard let acceptedAt else { return false }
        return now.timeIntervalSince(acceptedAt) > duration
    }

    func timeRemaining(now: Date) -> TimeInterval {
        guard let acceptedAt else { return duration }
        return max(0, duration - now.timeIntervalSince(acceptedAt))
    }
}

enum ContractStatus: String, Codable {
    case available
    case accepted
    case completed
    case expired
}

/// Pure resolution logic for contracts — no persistence, no networking.
enum EconomyEngine {
    static func canComplete(_ contract: Contract, playerResources: ResourceBag) -> Bool {
        contract.status == .accepted && playerResources.canAfford(contract.requiredResources)
    }

    /// Deducts the contract's cost and returns the resulting resources plus the
    /// reward to grant. Callers are responsible for persisting both.
    static func complete(_ contract: Contract, playerResources: ResourceBag) -> (resources: ResourceBag, reward: ResourceBag, experience: Double)? {
        guard canComplete(contract, playerResources: playerResources) else { return nil }
        var resources = playerResources
        for (resource, amount) in contract.requiredResources {
            resources[resource, default: 0] -= amount
        }
        resources.add(contract.rewardResources)
        return (resources, contract.rewardResources, contract.rewardExperience)
    }

    /// A small, deterministic starter contract set for the Farm vertical slice
    /// (§50: "Player completes City Contract: Deliver 100 Food").
    static func starterContracts() -> [Contract] {
        [
            Contract(
                id: UUID(),
                title: "Deliver 100 Food",
                flavorText: "The coast district's first shipment order.",
                requiredResources: [.food: 100],
                rewardResources: [.coins: 400],
                rewardExperience: 60,
                duration: 4 * 3600,
                status: .available,
                acceptedAt: nil
            ),
        ]
    }
}
