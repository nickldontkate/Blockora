import Foundation

/// A single cell in a building's local module grid. (0,0) is the foundation row's
/// leftmost cell; y increases upward, x increases rightward. Buildings are small
/// (MVP caps around 6x6), so `Int` coordinates are more than sufficient.
struct GridPosition: Hashable, Codable, Comparable {
    var x: Int
    var y: Int

    static func < (lhs: GridPosition, rhs: GridPosition) -> Bool {
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.x < rhs.x
    }

    /// Orthogonal neighbors only — Blockora's modular grid connects up/down/left/right.
    /// Diagonal "bridge" connections are a documented future extension (see spec §2)
    /// and intentionally excluded from MVP adjacency.
    func orthogonalNeighbors() -> [GridDirection: GridPosition] {
        [
            .up: GridPosition(x: x, y: y + 1),
            .down: GridPosition(x: x, y: y - 1),
            .left: GridPosition(x: x - 1, y: y),
            .right: GridPosition(x: x + 1, y: y),
        ]
    }
}

enum GridDirection: CaseIterable {
    case up, down, left, right

    var opposite: GridDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    var offset: (dx: Int, dy: Int) {
        switch self {
        case .up: return (0, 1)
        case .down: return (0, -1)
        case .left: return (-1, 0)
        case .right: return (1, 0)
        }
    }
}
