import Foundation

/// A module actually placed in a building. Mutable per-instance state (health,
/// construction progress, online/offline) lives here; the shared stats live on
/// the `ModuleDefinition` it points to.
struct ModuleInstance: Identifiable, Codable, Hashable {
    let id: UUID
    let definitionID: String
    var position: GridPosition

    /// 0 while under construction, 1 once workers finish (§9).
    var constructionProgress: Double
    var assignedWorkerIDs: Set<UUID>

    /// 0...1, reduced by structural stress or neglect; feeds ProductionEngine's
    /// condition multiplier.
    var health: Double

    /// Set by StructuralEngine each evaluation; drives connection-color visuals (§6).
    var connectionState: ConnectionState

    /// Set by ProductionEngine/StructuralEngine: false if missing a required
    /// connection (power/core) or structurally disconnected from ground.
    var isOnline: Bool

    /// Synergy ids currently applying to this module (for visuals + codex).
    var activeSynergyIDs: Set<String>

    /// Player paid to structurally reinforce this module (§7's REINFORCE
    /// action), boosting its effective support capacity in StructuralEngine.
    /// Optional for the same backward-compatibility reason as
    /// `PlayerProfile.dailyBonusStreak`: a save written before this field
    /// existed must still decode instead of falling back to `.newGame()`.
    var isReinforced: Bool?

    init(
        id: UUID = UUID(),
        definitionID: String,
        position: GridPosition,
        constructionProgress: Double = 0,
        assignedWorkerIDs: Set<UUID> = [],
        health: Double = 1,
        connectionState: ConnectionState = .safe,
        isOnline: Bool = false,
        activeSynergyIDs: Set<String> = [],
        isReinforced: Bool = false
    ) {
        self.id = id
        self.definitionID = definitionID
        self.position = position
        self.constructionProgress = constructionProgress
        self.assignedWorkerIDs = assignedWorkerIDs
        self.health = health
        self.connectionState = connectionState
        self.isOnline = isOnline
        self.activeSynergyIDs = activeSynergyIDs
        self.isReinforced = isReinforced
    }

    var isBuilt: Bool { constructionProgress >= 1 }

    var definition: ModuleDefinition? { ModuleCatalog.definition(for: definitionID) }
}

/// Visual/logical stress tier a module can be in, per §6.
enum ConnectionState: String, Codable {
    case safe
    case warning
    case danger

    var displayName: String {
        switch self {
        case .safe: return "Stable"
        case .warning: return "Stressed"
        case .danger: return "Overload"
        }
    }
}
