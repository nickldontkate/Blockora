import Foundation

/// The full persistent state of one player's city. This is the single source
/// of truth every engine reads and GameSession mutates — the SpriteKit scene
/// and SwiftUI views only ever observe it through GameSession, never hold
/// their own copy (§59: no view may invent state the model doesn't have).
struct GameWorld: Codable {
    var player: PlayerProfile
    var districts: [District]
    var plots: [Plot]
    var buildings: [UUID: BuildingInstance]
    var workers: [Worker]
    var contracts: [Contract]
    var worldEvents: [WorldEvent]
    var blueprints: [Blueprint]
    /// Optional so a save written before the World Project existed still
    /// decodes (see `PlayerProfile.dailyBonusStreak` for why this pattern is
    /// used throughout instead of a non-optional default).
    var worldProject: WorldProjectState?

    func building(on plotID: UUID) -> BuildingInstance? {
        guard let plot = plots.first(where: { $0.id == plotID }), let buildingID = plot.buildingID else { return nil }
        return buildings[buildingID]
    }

    /// The very first playable plot — the tiny construction site from §1/§53.
    static func newGame() -> GameWorld {
        let coastDistrict = District(
            id: UUID(),
            name: "Coast District",
            isUnlocked: true,
            // Coastal siting bonus (§24/§25) — the reason to care *where* a
            // building sits, not just what's in it.
            productionModifiers: [.food: 1.15],
            plotIDs: []
        )

        let firstPlot = Plot(id: UUID(), districtID: coastDistrict.id, worldPosition: GridPosition(x: 0, y: 0), buildingID: nil, isUnlocked: true, unlockCost: [:])
        let secondPlot = Plot(id: UUID(), districtID: coastDistrict.id, worldPosition: GridPosition(x: 1, y: 0), buildingID: nil, isUnlocked: false, unlockCost: [.coins: 800])
        let thirdPlot = Plot(id: UUID(), districtID: coastDistrict.id, worldPosition: GridPosition(x: 2, y: 0), buildingID: nil, isUnlocked: false, unlockCost: [.coins: 2200])

        var district = coastDistrict
        district.plotIDs = [firstPlot.id, secondPlot.id, thirdPlot.id]

        let starterWorkers = [
            Worker(name: "Mara", type: .builder),
            Worker(name: "Theo", type: .builder),
            Worker(name: "Priya", type: .engineer),
            Worker(name: "Sam", type: .electrician),
            Worker(name: "Yuki", type: .technician),
        ]

        return GameWorld(
            player: .newPlayer(),
            districts: [district],
            plots: [firstPlot, secondPlot, thirdPlot],
            buildings: [:],
            workers: starterWorkers,
            contracts: EconomyEngine.starterContracts(),
            worldEvents: [WorldEventEngine.techBoom(starting: Date())],
            blueprints: [],
            worldProject: .skybridge()
        )
    }
}
