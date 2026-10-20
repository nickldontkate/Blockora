import Foundation
import CoreGraphics
import Observation

/// A one-off UI event the scene/HUD should react to but that isn't part of
/// persistent state (a toast, a collapse VFX cue, a truck to spawn).
enum GameEvent: Identifiable {
    case synergyDiscovered(SynergyOccurrence)
    case structuralCollapse(buildingID: UUID, positions: Set<GridPosition>)
    case delivery(buildingID: UUID, job: DeliveryJob)
    case moduleCompleted(buildingID: UUID, position: GridPosition)
    case contractCompleted(Contract)
    case levelUp(newLevel: Int)
    case worldEventStarted(WorldEvent)

    var id: String {
        switch self {
        case .synergyDiscovered(let occurrence): return "synergy-\(occurrence.id)"
        case .structuralCollapse(let buildingID, _): return "collapse-\(buildingID)-\(UUID())"
        case .delivery(_, let job): return "delivery-\(job.id)"
        case .moduleCompleted(let buildingID, let position): return "complete-\(buildingID)-\(position.x)-\(position.y)-\(UUID())"
        case .contractCompleted(let contract): return "contract-\(contract.id)"
        case .levelUp(let level): return "levelup-\(level)"
        case .worldEventStarted(let event): return "worldevent-\(event.id)"
        }
    }
}

/// Cached, derived-from-`world` state for one building, recomputed whenever
/// that building's modules change. Nothing here is persisted — it's always
/// reproducible from `world` alone (§43's determinism carried up a level).
struct BuildingReport {
    var structural: StructuralReport
    var synergy: SynergyReport
    var production: ProductionResult
}

/// The seam between SwiftUI, SpriteKit and the engines. Owns the authoritative
/// `world`, recomputes derived reports, runs the real-time production tick,
/// and is the only thing that talks to `EconomyService`.
@MainActor
@Observable
final class GameSession {
    private(set) var world: GameWorld
    private(set) var buildingReports: [UUID: BuildingReport] = [:]
    private(set) var pendingEvents: [GameEvent] = []
    private(set) var pendingOfflineSummary: OfflineSimulationResult?
    var activeBuildingID: UUID?
    var isConstructionModeActive = false
    var pendingPlotSelectionID: UUID?
    var pendingPlotUnlockID: UUID?
    /// The streak day (1...7) a claim would land on right now, or nil if
    /// today's bonus is already claimed. RootView shows the claim overlay
    /// whenever this is non-nil.
    var pendingDailyBonusDay: Int?

    /// The tutorial step to hint at right now, or nil once the player has
    /// finished onboarding (or had it backfilled as already-done on load).
    var activeOnboardingStep: OnboardingStep? { OnboardingEngine.step(fromRaw: world.player.onboardingStep) }

    var unlockedBuildingClasses: [BuildingClass] {
        BuildingClass.allCases.filter { ProgressionEngine.isBuildingClassUnlocked($0, level: world.player.level) }
    }

    private var deliveryAccumulators: [String: Double] = [:] // "buildingID-resource"
    private var timeSinceLastAutosave: TimeInterval = 0
    /// How often continuous tick-driven progress (resource accrual) gets
    /// flushed to disk. Discrete events (placing a module, a completed
    /// build) still persist immediately — this only bounds how much of the
    /// *in-between* accrual an app kill can lose (§49: local-first, but
    /// still needs to survive being killed mid-session, not just quit
    /// cleanly).
    private static let autosaveInterval: TimeInterval = 15
    /// How many plots a single district can grow to before the player needs
    /// a whole new district instead (not yet implemented — this cap just
    /// keeps one district from growing forever in the meantime).
    private static let districtMaxPlots = 6
    private var completedAModuleThisTick = false
    private let service: EconomyService

    /// How often (in elapsed game seconds) the world re-rolls whether a new
    /// World Event should start (§23).
    private static let worldEventCheckInterval: TimeInterval = 45
    private static let worldEventStartChance = 0.35
    private var timeSinceLastWorldEventRoll: TimeInterval = 0
    /// The active-event set as of the last check, so a start/end can trigger
    /// a full production recompute exactly once rather than every frame.
    private var lastActiveWorldEventIDs: Set<UUID> = []

    init(service: EconomyService? = nil) {
        self.service = service ?? LocalEconomyService()
        self.world = .newGame()
    }

    // MARK: - Lifecycle

    func loadGame() async {
        world = (try? await service.loadWorld()) ?? .newGame()
        if world.worldProject == nil { world.worldProject = .skybridge() }
        if world.player.onboardingStep == nil {
            world.player.onboardingStep = OnboardingEngine.initialValue(hasExistingBuildings: !world.buildings.isEmpty)
        }
        lastActiveWorldEventIDs = Set(WorldEventEngine.activeEvents(world.worldEvents, at: Date()).map(\.id))
        recomputeAllReports()
        await claimOfflineRewardsIfNeeded()
        refreshDailyBonusAvailability()
    }

    private func refreshDailyBonusAvailability() {
        let now = Date()
        guard DailyBonusEngine.isAvailable(lastClaimDate: world.player.lastDailyBonusClaimDate, now: now) else {
            pendingDailyBonusDay = nil
            return
        }
        pendingDailyBonusDay = DailyBonusEngine.nextStreakDay(
            currentStreak: world.player.dailyBonusStreak ?? 0, lastClaimDate: world.player.lastDailyBonusClaimDate, now: now
        )
    }

    /// Grants the currently-pending daily bonus. Recomputes the streak day
    /// fresh (rather than trusting whatever `pendingDailyBonusDay` was set to
    /// at load time) so a claim can't be replayed by re-showing a stale overlay.
    func claimDailyBonus() {
        let now = Date()
        guard DailyBonusEngine.isAvailable(lastClaimDate: world.player.lastDailyBonusClaimDate, now: now) else {
            pendingDailyBonusDay = nil
            return
        }
        let day = DailyBonusEngine.nextStreakDay(
            currentStreak: world.player.dailyBonusStreak ?? 0, lastClaimDate: world.player.lastDailyBonusClaimDate, now: now
        )
        let reward = DailyBonusEngine.reward(forDay: day)
        for (resource, amount) in reward {
            let cap = world.player.storageCapacity[resource]
            var updated = world.player.resources[resource, default: 0] + amount
            if let cap { updated = min(updated, cap) }
            world.player.resources[resource] = updated
        }
        world.player.dailyBonusStreak = day
        world.player.lastDailyBonusClaimDate = now
        pendingDailyBonusDay = nil

        HapticManager.shared.contractCompleted()
        AudioManager.shared.play(.districtUnlock)
        persist()
    }

    func persist() {
        world.player.lastSyncDate = Date()
        Task { try? await service.saveWorld(world) }
    }

    func claimOfflineRewardsIfNeeded() async {
        guard let result = try? await service.claimOfflineRewards(world: world, now: Date()) else { return }
        world = result.world
        if result.result.elapsedSeconds > 60 {
            pendingOfflineSummary = result.result
        }
        recomputeAllReports()
    }

    // MARK: - Real-time tick (called from the SpriteKit scene's update loop)

    func tick(deltaSeconds: TimeInterval) {
        guard deltaSeconds > 0 else { return }
        let hours = deltaSeconds / 3600
        completedAModuleThisTick = false

        updateWorldEvents(deltaSeconds: deltaSeconds)

        for buildingID in world.buildings.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            advanceConstruction(buildingID: buildingID, deltaSeconds: deltaSeconds)
            guard let report = buildingReports[buildingID] else { continue }
            for (resource, rate) in report.production.netPerHour {
                let delta = rate * hours
                let cap = world.player.storageCapacity[resource]
                var updated = (world.player.resources[resource] ?? 0) + delta
                if let cap { updated = min(updated, cap) }
                world.player.resources[resource] = max(0, updated)
                if delta > 0 { accumulateDelivery(buildingID: buildingID, resource: resource, amount: delta) }
            }
        }

        timeSinceLastAutosave += deltaSeconds
        if completedAModuleThisTick || timeSinceLastAutosave >= Self.autosaveInterval {
            timeSinceLastAutosave = 0
            persist()
        }
    }

    private func accumulateDelivery(buildingID: UUID, resource: ResourceType, amount: Double) {
        let key = "\(buildingID)-\(resource.rawValue)"
        var accumulated = (deliveryAccumulators[key] ?? 0) + amount
        if let job = LogisticsEngine.spawnDelivery(
            for: resource, accumulated: &accumulated,
            origin: .zero, destination: .zero, road: .paved
        ) {
            pendingEvents.append(.delivery(buildingID: buildingID, job: job))
        }
        deliveryAccumulators[key] = accumulated
    }

    private func advanceConstruction(buildingID: UUID, deltaSeconds: TimeInterval) {
        guard var building = world.buildings[buildingID] else { return }
        var changed = false
        for (position, var module) in building.modules where !module.isBuilt {
            guard let definition = module.definition else { continue }
            topUpAssignment(module: &module, definition: definition)

            let assignedWorkers = world.workers.filter { module.assignedWorkerIDs.contains($0.id) }
            let (updated, didComplete) = WorkerAssignmentEngine.advance(
                module: module, definition: definition, workers: assignedWorkers, deltaSeconds: deltaSeconds
            )
            building.modules[position] = updated
            changed = true
            if didComplete {
                releaseWorkers(assignedTo: updated.id)
                pendingEvents.append(.moduleCompleted(buildingID: buildingID, position: position))
                HapticManager.shared.modulePlaced()
                AudioManager.shared.play(.constructionComplete)
                completedAModuleThisTick = true
            }
        }
        if changed {
            world.buildings[buildingID] = building
            recomputeReport(for: buildingID)
        }
    }

    /// Fills any still-open crew slots on an in-progress module from currently
    /// idle workers. Runs every tick (not just at placement) so a module
    /// placed while every matching worker is busy elsewhere still picks up
    /// crew the moment one frees up, instead of sitting at 0% forever (§9).
    private func topUpAssignment(module: inout ModuleInstance, definition: ModuleDefinition) {
        var remaining = definition.workersRequired
        for workerID in module.assignedWorkerIDs {
            guard let worker = world.workers.first(where: { $0.id == workerID }), let need = remaining[worker.type] else { continue }
            remaining[worker.type] = max(0, need - 1)
        }
        guard remaining.values.contains(where: { $0 > 0 }) else { return }

        for index in world.workers.indices {
            guard world.workers[index].isAvailable else { continue }
            guard let need = remaining[world.workers[index].type], need > 0 else { continue }
            world.workers[index].assignedModuleID = module.id
            module.assignedWorkerIDs.insert(world.workers[index].id)
            remaining[world.workers[index].type] = need - 1
        }
    }

    /// Sends a module's crew back to idle once it's built, so they're free to
    /// pick up the next placement.
    private func releaseWorkers(assignedTo moduleID: UUID) {
        for index in world.workers.indices where world.workers[index].assignedModuleID == moduleID {
            world.workers[index].assignedModuleID = nil
        }
    }

    /// Rolls new World Events in and prunes stale history (§23), and forces a
    /// full production recompute the moment the *active* event set actually
    /// changes — otherwise a started/ended event wouldn't affect output until
    /// some unrelated change (a placement, a completion) happened to trigger
    /// one on its own.
    private func updateWorldEvents(deltaSeconds: TimeInterval) {
        let now = Date()

        timeSinceLastWorldEventRoll += deltaSeconds
        if timeSinceLastWorldEventRoll >= Self.worldEventCheckInterval {
            timeSinceLastWorldEventRoll = 0
            world.worldEvents.removeAll { $0.endDate < now.addingTimeInterval(-3600) }
            let currentlyActive = WorldEventEngine.activeEvents(world.worldEvents, at: now)
            if currentlyActive.isEmpty, Double.random(in: 0...1) < Self.worldEventStartChance {
                let event = WorldEventEngine.randomEvent(starting: now)
                world.worldEvents.append(event)
                pendingEvents.append(.worldEventStarted(event))
                HapticManager.shared.contractCompleted()
                AudioManager.shared.play(.districtUnlock)
            }
        }

        let activeIDs = Set(WorldEventEngine.activeEvents(world.worldEvents, at: now).map(\.id))
        if activeIDs != lastActiveWorldEventIDs {
            lastActiveWorldEventIDs = activeIDs
            recomputeAllReports()
        }
    }

    // MARK: - Construction

    func beginConstruction(on plotID: UUID, buildingClass: BuildingClass) {
        guard let plotIndex = world.plots.firstIndex(where: { $0.id == plotID }), world.plots[plotIndex].isBuildable else { return }
        let building = BuildingInstance(buildingClass: buildingClass, plotID: plotID, displayName: buildingClass.displayName)
        world.buildings[building.id] = building
        world.plots[plotIndex].buildingID = building.id
        activeBuildingID = building.id
        isConstructionModeActive = true
        pendingPlotSelectionID = nil
        world.player.onboardingStep = OnboardingEngine.advance(current: world.player.onboardingStep, ifAt: .tapPlot)
        recomputeReport(for: building.id)
        persist()
    }

    /// Called when a plot is tapped and it isn't obvious which building class
    /// to start (more than one is unlocked) — RootView shows a chooser bound
    /// to `pendingPlotSelectionID` and calls this once the player picks.
    func chooseBuildingClass(_ buildingClass: BuildingClass, for plotID: UUID) {
        beginConstruction(on: plotID, buildingClass: buildingClass)
    }

    func requestPlotInteraction(_ plotID: UUID) {
        guard let plot = world.plots.first(where: { $0.id == plotID }) else { return }
        if !plot.isUnlocked {
            pendingPlotUnlockID = plotID
        } else if let buildingID = plot.buildingID {
            activeBuildingID = buildingID
            isConstructionModeActive = true
        } else if unlockedBuildingClasses.count == 1, let only = unlockedBuildingClasses.first {
            beginConstruction(on: plotID, buildingClass: only)
        } else {
            pendingPlotSelectionID = plotID
        }
    }

    func confirmUnlockPlot(_ plotID: UUID) {
        guard let index = world.plots.firstIndex(where: { $0.id == plotID }) else { return }
        let cost = world.plots[index].unlockCost
        guard world.player.resources.canAfford(cost) else {
            HapticManager.shared.actionFailed()
            return
        }
        for (resource, amount) in cost { world.player.resources[resource, default: 0] -= amount }
        world.plots[index].isUnlocked = true
        pendingPlotUnlockID = nil
        AudioManager.shared.play(.districtUnlock)
        expandDistrictIfNeeded(districtID: world.plots[index].districtID)
        persist()
    }

    /// Once every plot in a district is unlocked, grows the district by one
    /// more (pricier) plot instead of leaving the island permanently capped
    /// at its starter size (§1/§24).
    private func expandDistrictIfNeeded(districtID: UUID) {
        guard let districtIndex = world.districts.firstIndex(where: { $0.id == districtID }) else { return }
        let districtPlots = world.plots.filter { $0.districtID == districtID }
        guard PlotExpansionEngine.shouldExpand(districtPlots: districtPlots, maxPlots: Self.districtMaxPlots) else { return }

        let cost = PlotExpansionEngine.nextUnlockCost(districtPlots: districtPlots)
        let position = PlotExpansionEngine.nextWorldPosition(districtPlots: districtPlots)
        let newPlot = Plot(
            id: UUID(), districtID: districtID, worldPosition: position,
            buildingID: nil, isUnlocked: false, unlockCost: [.coins: cost]
        )
        world.plots.append(newPlot)
        world.districts[districtIndex].plotIDs.append(newPlot.id)
    }

    func exitConstructionMode() {
        isConstructionModeActive = false
        activeBuildingID = nil
        world.player.onboardingStep = OnboardingEngine.advance(current: world.player.onboardingStep, ifAt: .finishConstruction)
    }

    /// Called when the player opens any bottom tab for the first time, to
    /// retire the last onboarding hint ("go explore the tabs").
    func acknowledgeTabExplored() {
        let updated = OnboardingEngine.advance(current: world.player.onboardingStep, ifAt: .exploreTabs)
        guard updated != world.player.onboardingStep else { return }
        world.player.onboardingStep = updated
        persist()
    }

    func availableModules(for buildingID: UUID) -> [ModuleDefinition] {
        guard let building = world.buildings[buildingID] else { return [] }
        return ModuleCatalog.modules(for: building.buildingClass, unlockedUpTo: world.player.level)
    }

    func preview(buildingID: UUID, definitionID: String, at position: GridPosition) -> PlacementPreview? {
        guard let building = world.buildings[buildingID], let definition = ModuleCatalog.definition(for: definitionID) else { return nil }
        return ConstructionEngine.preview(building: building, definition: definition, at: position, playerLevel: world.player.level, playerResources: world.player.resources)
    }

    @discardableResult
    func placeModule(buildingID: UUID, definitionID: String, at position: GridPosition) -> Bool {
        guard let building = world.buildings[buildingID], let definition = ModuleCatalog.definition(for: definitionID) else { return false }
        let validation = ConstructionEngine.validatePlacement(building: building, definition: definition, at: position, playerLevel: world.player.level, playerResources: world.player.resources)
        guard validation.isValid else {
            HapticManager.shared.actionFailed()
            return false
        }

        var world = self.world
        for (resource, amount) in definition.placementCost {
            world.player.resources[resource, default: 0] -= amount
        }
        world.buildings[buildingID] = ConstructionEngine.place(building: building, definitionID: definitionID, at: position)
        self.world = world

        switch self.world.buildings[buildingID]?.modules.count ?? 0 {
        case 1: self.world.player.onboardingStep = OnboardingEngine.advance(current: self.world.player.onboardingStep, ifAt: .placeFoundation)
        case 2...: self.world.player.onboardingStep = OnboardingEngine.advance(current: self.world.player.onboardingStep, ifAt: .addAnotherModule)
        default: break
        }

        HapticManager.shared.modulePlaced()
        AudioManager.shared.play(.modulePlace)
        recomputeReport(for: buildingID)
        persist()
        return true
    }

    func removeModule(buildingID: UUID, at position: GridPosition) {
        guard let building = world.buildings[buildingID] else { return }
        world.buildings[buildingID] = ConstructionEngine.remove(building: building, at: position)
        recomputeReport(for: buildingID)
        persist()
    }

    /// Tears the whole building down (§7's "start over" option) and frees its
    /// plot for a fresh build. Destructive and uncompensated by design — like
    /// Settings' "Reset Game", the UI is expected to confirm before calling
    /// this, not this method itself.
    func demolishBuilding(_ buildingID: UUID) {
        guard let building = world.buildings[buildingID] else { return }
        if let plotIndex = world.plots.firstIndex(where: { $0.id == building.plotID }) {
            world.plots[plotIndex].buildingID = nil
        }
        for moduleID in building.modules.values.map(\.id) {
            releaseWorkers(assignedTo: moduleID)
        }
        world.buildings.removeValue(forKey: buildingID)
        buildingReports.removeValue(forKey: buildingID)
        if activeBuildingID == buildingID { exitConstructionMode() }
        persist()
    }

    /// Pays to reinforce every currently stressed (warning/danger) module in
    /// a building, worst stress first, spending only as far as the player can
    /// afford (§7's proactive REINFORCE, as an alternative to waiting for a
    /// collapse and rebuilding).
    @discardableResult
    func reinforceStressedModules(buildingID: UUID) -> Int {
        guard let building = world.buildings[buildingID], let report = buildingReports[buildingID] else { return 0 }
        let candidates = report.structural.statuses
            .filter { $0.value.connectionState != .safe }
            .sorted { $0.value.stressRatio > $1.value.stressRatio }
            .map(\.key)

        var updatedBuilding = building
        var reinforcedCount = 0
        for position in candidates {
            guard var module = updatedBuilding.modules[position], module.isReinforced != true,
                  let definition = module.definition else { continue }
            let cost = ConstructionEngine.reinforcementCost(for: definition)
            guard world.player.resources.canAfford(cost) else { continue }
            for (resource, amount) in cost { world.player.resources[resource, default: 0] -= amount }
            module.isReinforced = true
            updatedBuilding.modules[position] = module
            reinforcedCount += 1
        }

        guard reinforcedCount > 0 else {
            HapticManager.shared.actionFailed()
            return 0
        }
        world.buildings[buildingID] = updatedBuilding
        HapticManager.shared.modulePlaced()
        AudioManager.shared.play(.modulePlace)
        recomputeReport(for: buildingID)
        persist()
        return reinforcedCount
    }

    // MARK: - Blueprints

    /// Snapshots a building's current module layout into a reusable Blueprint
    /// (§28). Only the layout is stored — placing it later still consumes
    /// real resources through the normal `placeModule` path.
    @discardableResult
    func saveBlueprint(for buildingID: UUID, name: String) -> Bool {
        guard let building = world.buildings[buildingID], !building.modules.isEmpty else { return false }
        let structural = StructuralEngine.evaluate(modules: building.modules)
        let synergy = SynergyEngine.evaluate(modules: building.modules, playerLevel: world.player.level)
        let production = ProductionEngine.evaluate(building: building, structural: structural, synergy: synergy)
        let operationalRatios = production.operationalRatio.values
        let efficiency = operationalRatios.isEmpty ? 100.0 : (operationalRatios.reduce(0, +) / Double(operationalRatios.count)) * 100

        let blueprint = Blueprint(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? building.displayName : name,
            buildingClass: building.buildingClass,
            moduleDefinitionIDs: building.modules.mapValues(\.definitionID),
            createdAt: Date(),
            summary: BlueprintSummary(
                efficiencyPercent: efficiency,
                netProduction: production.netPerHour,
                stabilityPercent: structural.overallHealthPercent * 100,
                synergyCount: synergy.occurrences.count
            )
        )
        world.blueprints.append(blueprint)
        HapticManager.shared.contractCompleted()
        persist()
        return true
    }

    /// Replays a saved Blueprint's layout onto an empty building of the same
    /// class, placing each module through the normal validated path so cost
    /// and level gating still apply. Stops at the first module the player
    /// can't afford or place, in the blueprint's own position order, so a
    /// half-applied result still reads as "front of the design," not scattered.
    @discardableResult
    func applyBlueprint(_ blueprint: Blueprint, to buildingID: UUID) -> Int {
        guard let building = world.buildings[buildingID], building.isEmpty,
              building.buildingClass == blueprint.buildingClass else { return 0 }

        let orderedPositions = blueprint.moduleDefinitionIDs.keys.sorted()
        var placedCount = 0
        for position in orderedPositions {
            guard let definitionID = blueprint.moduleDefinitionIDs[position] else { continue }
            if placeModule(buildingID: buildingID, definitionID: definitionID, at: position) {
                placedCount += 1
            }
        }
        return placedCount
    }

    // MARK: - World Project

    /// Puts real resources toward the shared build (§31). Local-only until a
    /// backend exists to actually share the total across players — see
    /// `WorldProjectView`'s disclosure text.
    @discardableResult
    func contributeToWorldProject(_ resource: ResourceType, amount: Double) -> Bool {
        guard amount > 0, var project = world.worldProject, !project.isComplete else { return false }
        let contribution = WorldProjectEngine.clampedContribution(amount, resource: resource, state: project)
        guard contribution > 0, world.player.resources.canAfford([resource: contribution]) else {
            HapticManager.shared.actionFailed()
            return false
        }
        world.player.resources[resource, default: 0] -= contribution
        project.contributed[resource, default: 0] += contribution

        if WorldProjectEngine.isComplete(project) {
            project.isComplete = true
            for (resource, amount) in WorldProjectEngine.completionReward() {
                let cap = world.player.storageCapacity[resource]
                var updated = world.player.resources[resource, default: 0] + amount
                if let cap { updated = min(updated, cap) }
                world.player.resources[resource] = updated
            }
            HapticManager.shared.contractCompleted()
            AudioManager.shared.play(.districtUnlock)
        } else {
            HapticManager.shared.modulePlaced()
            AudioManager.shared.play(.resourceCollect)
        }

        world.worldProject = project
        persist()
        return true
    }

    // MARK: - Contracts

    func acceptContract(_ contractID: UUID) {
        guard let index = world.contracts.firstIndex(where: { $0.id == contractID }) else { return }
        world.contracts[index].status = .accepted
        world.contracts[index].acceptedAt = Date()
        persist()
    }

    func completeContract(_ contractID: UUID) {
        guard let index = world.contracts.firstIndex(where: { $0.id == contractID }) else { return }
        let contract = world.contracts[index]
        guard let result = EconomyEngine.complete(contract, playerResources: world.player.resources) else {
            HapticManager.shared.actionFailed()
            return
        }
        world.player.resources = result.resources
        let progression = ProgressionEngine.applyExperience(result.experience, level: world.player.level, experience: world.player.experience)
        let didLevelUp = progression.didLevelUp
        world.player.level = progression.level
        world.player.experience = progression.experience
        world.contracts[index].status = .completed

        HapticManager.shared.contractCompleted()
        AudioManager.shared.play(.contractComplete)
        pendingEvents.append(.contractCompleted(world.contracts[index]))
        if didLevelUp { pendingEvents.append(.levelUp(newLevel: world.player.level)) }
        persist()
    }

    // MARK: - Derived state

    /// Visual/world reactions: collapse VFX, delivery trucks, construction completion pulses.
    /// Called every frame from the scene's update loop, so this must not touch
    /// the (observation-tracked) `pendingEvents` array when there's nothing to
    /// do — a no-op `removeAll` still fires an Observable change notification,
    /// which was forcing a full SwiftUI re-render 60 times a second.
    func consumeSceneEvents() -> [GameEvent] {
        guard !pendingEvents.isEmpty else { return [] }
        var scene: [GameEvent] = []
        pendingEvents.removeAll { event in
            switch event {
            case .structuralCollapse, .delivery, .moduleCompleted:
                scene.append(event)
                return true
            default:
                return false
            }
        }
        return scene
    }

    /// HUD toasts: synergy discovery, contract completion, level up.
    func consumeToastEvents() -> [GameEvent] {
        guard !pendingEvents.isEmpty else { return [] }
        var toasts: [GameEvent] = []
        pendingEvents.removeAll { event in
            switch event {
            case .synergyDiscovered, .contractCompleted, .levelUp, .worldEventStarted:
                toasts.append(event)
                return true
            default:
                return false
            }
        }
        return toasts
    }

    func consumeOfflineSummary() -> OfflineSimulationResult? {
        defer { pendingOfflineSummary = nil }
        return pendingOfflineSummary
    }

    private func recomputeAllReports() {
        for buildingID in world.buildings.keys { recomputeReport(for: buildingID) }
    }

    private func recomputeReport(for buildingID: UUID) {
        guard let building = world.buildings[buildingID] else { return }
        let previouslyKnown = buildingReports[buildingID]?.synergy.discoveredDefinitionIDs

        let (updatedBuilding, collapsed) = ConstructionEngine.resolveCollapse(building: building)
        if !collapsed.isEmpty {
            world.buildings[buildingID] = updatedBuilding
            HapticManager.shared.structuralCollapse()
            AudioManager.shared.play(.collapse)
            pendingEvents.append(.structuralCollapse(buildingID: buildingID, positions: collapsed))
        }

        let structural = StructuralEngine.evaluate(modules: updatedBuilding.modules)
        let synergy = SynergyEngine.evaluate(modules: updatedBuilding.modules, playerLevel: world.player.level)
        let districtModifiers = world.plots.first(where: { $0.id == updatedBuilding.plotID })
            .flatMap { plot in world.districts.first(where: { $0.id == plot.districtID }) }?
            .productionModifiers ?? [:]
        let eventModifiers = WorldEventEngine.combinedModifiers(world.worldEvents, at: Date())
        let production = ProductionEngine.evaluate(
            building: updatedBuilding, structural: structural, synergy: synergy,
            districtModifiers: districtModifiers, eventModifiers: eventModifiers
        )
        buildingReports[buildingID] = BuildingReport(structural: structural, synergy: synergy, production: production)

        let newlyDiscovered = synergy.discoveredDefinitionIDs.subtracting(previouslyKnown ?? [])
        for id in newlyDiscovered where world.player.discoveredSynergyIDs.insert(id).inserted {
            if let occurrence = synergy.occurrences.first(where: { $0.definitionID == id }) {
                HapticManager.shared.synergyDiscovered()
                AudioManager.shared.play(.synergyDiscovered)
                pendingEvents.append(.synergyDiscovered(occurrence))
            }
        }
    }
}
