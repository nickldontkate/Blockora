import Foundation

/// City demand framing (§21): the player asks "what should my city produce?",
/// never "buy low, sell high." This is read-only market color derived from
/// active world events — there is no buy/sell action anywhere in the game.
struct MarketDemandLevel {
    var resource: ResourceType
    var multiplier: Double

    var label: String {
        switch multiplier {
        case ..<0.9: return "Low"
        case 0.9..<1.15: return "Normal"
        case 1.15..<1.5: return "High"
        default: return "Very High"
        }
    }
}

enum MarketDemand {
    static func current(events: [WorldEvent], at date: Date) -> [MarketDemandLevel] {
        let modifiers = WorldEventEngine.combinedModifiers(events, at: date)
        return ResourceType.allCases
            .filter { $0 != .coins && $0 != .blocks }
            .map { MarketDemandLevel(resource: $0, multiplier: modifiers[$0] ?? 1.0) }
    }
}
