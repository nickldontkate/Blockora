import Foundation

/// Decides when a district should grow a new, pricier plot once every plot it
/// currently has is unlocked — the island keeps growing past the three
/// starter plots instead of hard-capping the player's city (§1/§24: "tiny
/// island becomes a huge city" is an ongoing process, not a one-time reveal).
enum PlotExpansionEngine {
    static let costGrowthFactor = 1.8

    static func shouldExpand(districtPlots: [Plot], maxPlots: Int) -> Bool {
        guard !districtPlots.isEmpty, districtPlots.count < maxPlots else { return false }
        return districtPlots.allSatisfy(\.isUnlocked)
    }

    /// Each new plot costs `costGrowthFactor`x the most expensive existing
    /// plot in the district, rounded to a clean number.
    static func nextUnlockCost(districtPlots: [Plot]) -> Double {
        let lastCost = districtPlots.compactMap { $0.unlockCost[.coins] }.max() ?? 500
        let raw = lastCost * costGrowthFactor
        return (raw / 100).rounded() * 100
    }

    static func nextWorldPosition(districtPlots: [Plot]) -> GridPosition {
        let maxX = districtPlots.map(\.worldPosition.x).max() ?? -1
        return GridPosition(x: maxX + 1, y: 0)
    }
}
