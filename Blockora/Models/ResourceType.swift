import Foundation

/// The economy's tradeable resources. Kept to a small, fixed set per design spec
/// (no ad-hoc currencies scattered through gameplay code).
enum ResourceType: String, Codable, CaseIterable, Identifiable {
    case coins
    case food
    case energy
    case goods
    case data
    case blocks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coins: return "Coins"
        case .food: return "Food"
        case .energy: return "Energy"
        case .goods: return "Goods"
        case .data: return "Data"
        case .blocks: return "Blocks"
        }
    }

    /// SF Symbol used across HUD, tray previews and world-space icons.
    var symbolName: String {
        switch self {
        case .coins: return "circlebadge.2.fill"
        case .food: return "leaf.fill"
        case .energy: return "bolt.fill"
        case .goods: return "shippingbox.fill"
        case .data: return "cube.transparent.fill"
        case .blocks: return "diamond.fill"
        }
    }
}

/// A signed amount of a resource. Used for production/consumption stats,
/// contract requirements and rewards.
struct ResourceAmount: Codable, Hashable {
    var type: ResourceType
    var amount: Double

    init(_ type: ResourceType, _ amount: Double) {
        self.type = type
        self.amount = amount
    }
}

typealias ResourceBag = [ResourceType: Double]

extension Dictionary where Key == ResourceType, Value == Double {
    static func + (lhs: ResourceBag, rhs: ResourceBag) -> ResourceBag {
        var result = lhs
        for (key, value) in rhs {
            result[key, default: 0] += value
        }
        return result
    }

    mutating func add(_ other: ResourceBag) {
        for (key, value) in other {
            self[key, default: 0] += value
        }
    }

    /// True if every entry in `other` can be subtracted without going negative.
    func canAfford(_ other: ResourceBag) -> Bool {
        for (key, value) in other where self[key, default: 0] < value {
            return false
        }
        return true
    }
}
