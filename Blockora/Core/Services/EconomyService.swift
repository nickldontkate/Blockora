import Foundation

/// Everything GameSession needs from "the backend" — whichever one is
/// currently backing it (§49). Every mutating call takes the current world and
/// returns the new world so Local and Remote can be swapped without
/// GameSession caring which one actually ran the logic.
protocol EconomyService {
    func loadWorld() async throws -> GameWorld
    func saveWorld(_ world: GameWorld) async throws

    func placeModule(world: GameWorld, buildingID: UUID, definitionID: String, at position: GridPosition) async throws -> GameWorld
    func removeModule(world: GameWorld, buildingID: UUID, at position: GridPosition) async throws -> GameWorld

    func acceptContract(world: GameWorld, contractID: UUID) async throws -> GameWorld
    func completeContract(world: GameWorld, contractID: UUID) async throws -> GameWorld

    func claimOfflineRewards(world: GameWorld, now: Date) async throws -> (world: GameWorld, result: OfflineSimulationResult)
}

enum EconomyServiceError: Error {
    case invalidPlacement(reasons: [String])
    case buildingNotFound
    case contractNotFound
    case contractNotFulfillable
}

/// Runs every rule client-side using the same engines a server would use
/// (§49). This is what the game plays against today; it's also exactly the
/// logic RemoteEconomyService's Cloudflare counterpart re-implements
/// server-authoritatively once that backend is live.
final class LocalEconomyService: EconomyService {
    private let store: SaveGameStore

    init(store: SaveGameStore = .shared) {
        self.store = store
    }

    func loadWorld() async throws -> GameWorld {
        store.load() ?? .newGame()
    }

    func saveWorld(_ world: GameWorld) async throws {
        store.save(world)
    }

    func placeModule(world: GameWorld, buildingID: UUID, definitionID: String, at position: GridPosition) async throws -> GameWorld {
        guard let definition = ModuleCatalog.definition(for: definitionID) else {
            throw EconomyServiceError.invalidPlacement(reasons: ["Unknown module."])
        }
        guard var building = world.buildings[buildingID] else { throw EconomyServiceError.buildingNotFound }

        let validation = ConstructionEngine.validatePlacement(
            building: building, definition: definition, at: position,
            playerLevel: world.player.level, playerResources: world.player.resources
        )
        guard validation.isValid else { throw EconomyServiceError.invalidPlacement(reasons: validation.reasons) }

        var world = world
        for (resource, amount) in definition.placementCost {
            world.player.resources[resource, default: 0] -= amount
        }
        building = ConstructionEngine.place(building: building, definitionID: definitionID, at: position)
        world.buildings[buildingID] = building
        return world
    }

    func removeModule(world: GameWorld, buildingID: UUID, at position: GridPosition) async throws -> GameWorld {
        guard let building = world.buildings[buildingID] else { throw EconomyServiceError.buildingNotFound }
        var world = world
        world.buildings[buildingID] = ConstructionEngine.remove(building: building, at: position)
        return world
    }

    func acceptContract(world: GameWorld, contractID: UUID) async throws -> GameWorld {
        guard let index = world.contracts.firstIndex(where: { $0.id == contractID }) else {
            throw EconomyServiceError.contractNotFound
        }
        var world = world
        world.contracts[index].status = .accepted
        world.contracts[index].acceptedAt = Date()
        return world
    }

    func completeContract(world: GameWorld, contractID: UUID) async throws -> GameWorld {
        guard let index = world.contracts.firstIndex(where: { $0.id == contractID }) else {
            throw EconomyServiceError.contractNotFound
        }
        var world = world
        let contract = world.contracts[index]
        guard let result = EconomyEngine.complete(contract, playerResources: world.player.resources) else {
            throw EconomyServiceError.contractNotFulfillable
        }
        world.player.resources = result.resources
        let progression = ProgressionEngine.applyExperience(result.experience, level: world.player.level, experience: world.player.experience)
        world.player.level = progression.level
        world.player.experience = progression.experience
        world.contracts[index].status = .completed
        return world
    }

    func claimOfflineRewards(world: GameWorld, now: Date) async throws -> (world: GameWorld, result: OfflineSimulationResult) {
        let result = OfflineSimulationEngine.simulate(
            resources: world.player.resources,
            storageCapacity: world.player.storageCapacity,
            buildings: Array(world.buildings.values),
            playerLevel: world.player.level,
            elapsedSince: world.player.lastSyncDate,
            now: now
        )
        var world = world
        world.player.resources = result.updatedResources
        world.player.lastSyncDate = now
        return (world, result)
    }
}

/// Talks to the Cloudflare Workers API instead of running rules locally.
/// Endpoint paths mirror `backend/` — see that package's README for the exact
/// request/response contract. Not the default service yet (see
/// `GameSession.makeDefaultEconomyService`); flipping to this is a one-line change.
final class RemoteEconomyService: EconomyService {
    private let client: APIClient

    init(client: APIClient = .cloudflare) {
        self.client = client
    }

    func loadWorld() async throws -> GameWorld {
        try await client.get("city")
    }

    func saveWorld(_ world: GameWorld) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await client.post("city/save", body: world)
    }

    func placeModule(world: GameWorld, buildingID: UUID, definitionID: String, at position: GridPosition) async throws -> GameWorld {
        struct Request: Encodable { let buildingID: UUID; let definitionID: String; let position: GridPosition }
        return try await client.post("buildings/place-module", body: Request(buildingID: buildingID, definitionID: definitionID, position: position))
    }

    func removeModule(world: GameWorld, buildingID: UUID, at position: GridPosition) async throws -> GameWorld {
        struct Request: Encodable { let buildingID: UUID; let position: GridPosition }
        return try await client.post("buildings/remove-module", body: Request(buildingID: buildingID, position: position))
    }

    func acceptContract(world: GameWorld, contractID: UUID) async throws -> GameWorld {
        struct Request: Encodable { let contractID: UUID }
        return try await client.post("contracts/accept", body: Request(contractID: contractID))
    }

    func completeContract(world: GameWorld, contractID: UUID) async throws -> GameWorld {
        struct Request: Encodable { let contractID: UUID }
        return try await client.post("contracts/complete", body: Request(contractID: contractID))
    }

    func claimOfflineRewards(world: GameWorld, now: Date) async throws -> (world: GameWorld, result: OfflineSimulationResult) {
        throw APIError.notImplemented
    }
}
