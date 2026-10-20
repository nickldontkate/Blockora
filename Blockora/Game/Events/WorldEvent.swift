import Foundation

/// A time-boxed global modifier (§23). Multipliers are applied on top of
/// synergy/district multipliers by ProductionEngine's caller.
struct WorldEvent: Identifiable, Codable {
    let id: UUID
    var title: String
    var flavorText: String
    var resourceModifiers: ResourceBag
    var startDate: Date
    var endDate: Date

    func isActive(at date: Date) -> Bool { date >= startDate && date < endDate }
}

enum WorldEventEngine {
    static func activeEvents(_ events: [WorldEvent], at date: Date) -> [WorldEvent] {
        events.filter { $0.isActive(at: date) }
    }

    /// Combines every active event's modifiers into one multiplier bag
    /// (multiplicative — two simultaneous +50% events compound to +125%).
    static func combinedModifiers(_ events: [WorldEvent], at date: Date) -> ResourceBag {
        var combined: ResourceBag = [:]
        for event in activeEvents(events, at: date) {
            for (resource, multiplier) in event.resourceModifiers {
                combined[resource] = (combined[resource] ?? 1.0) * multiplier
            }
        }
        return combined
    }

    /// A representative catalog entry so the world doesn't launch silent (§23).
    static func techBoom(starting date: Date) -> WorldEvent {
        WorldEvent(
            id: UUID(),
            title: "Tech Boom",
            flavorText: "Demand for Data is spiking across the region.",
            resourceModifiers: [.data: 1.80],
            startDate: date,
            endDate: date.addingTimeInterval(6 * 3600)
        )
    }

    static func harvestFestival(starting date: Date) -> WorldEvent {
        WorldEvent(
            id: UUID(),
            title: "Harvest Festival",
            flavorText: "The region is stocking up on Food for the festival.",
            resourceModifiers: [.food: 1.6],
            startDate: date,
            endDate: date.addingTimeInterval(5 * 3600)
        )
    }

    static func industrialSurge(starting date: Date) -> WorldEvent {
        WorldEvent(
            id: UUID(),
            title: "Industrial Surge",
            flavorText: "Factories nearby are buying up Goods at a premium.",
            resourceModifiers: [.goods: 1.7],
            startDate: date,
            endDate: date.addingTimeInterval(4 * 3600)
        )
    }

    static func energyShortage(starting date: Date) -> WorldEvent {
        WorldEvent(
            id: UUID(),
            title: "Energy Shortage",
            flavorText: "A regional grid fault is limiting Energy output.",
            resourceModifiers: [.energy: 0.65],
            startDate: date,
            endDate: date.addingTimeInterval(3 * 3600)
        )
    }

    /// Every event this catalog can roll, so callers never need to enumerate
    /// cases by hand when picking one at random.
    static let catalog: [(Date) -> WorldEvent] = [techBoom, harvestFestival, industrialSurge, energyShortage]

    static func randomEvent(starting date: Date) -> WorldEvent {
        (catalog.randomElement() ?? techBoom)(date)
    }
}
