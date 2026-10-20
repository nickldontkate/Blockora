import Foundation

/// Player-level progression state (§54). Deliberately just two currencies and
/// an XP counter — the spec explicitly warns against currency sprawl.
struct PlayerProfile: Codable {
    var id: UUID
    var displayName: String
    var level: Int
    var experience: Double
    var resources: ResourceBag
    var storageCapacity: ResourceBag
    var discoveredSynergyIDs: Set<String>
    var lastSyncDate: Date
    var lastDailyBonusClaimDate: Date?
    /// Optional (rather than defaulting to 0) purely so a save written before
    /// this field existed still decodes: a missing key on a non-optional,
    /// no-default stored property fails `Decodable` synthesis entirely and
    /// would silently reset the player's whole city back to `.newGame()`.
    var dailyBonusStreak: Int?
    /// Progress through the first-run tutorial (`OnboardingEngine`/`OnboardingStep`).
    /// Optional for the same backward-compatibility reason as the fields above.
    var onboardingStep: Int?

    static func newPlayer(id: UUID = UUID()) -> PlayerProfile {
        PlayerProfile(
            id: id,
            displayName: "Builder",
            level: 1,
            experience: 0,
            resources: [.coins: 500, .food: 0, .energy: 0, .goods: 0, .data: 0, .blocks: 5],
            storageCapacity: [.food: 300, .energy: 300, .goods: 200, .data: 200],
            discoveredSynergyIDs: [],
            lastSyncDate: Date(),
            lastDailyBonusClaimDate: nil,
            dailyBonusStreak: 0,
            onboardingStep: OnboardingStep.tapPlot.rawValue
        )
    }
}

/// XP thresholds and unlock gating (§54). A pure function of level — no hidden
/// state — so ProgressionEngine.unlocks(for:) is trivially testable.
enum ProgressionEngine {
    /// XP required to reach the *next* level from `level`.
    static func experienceToNextLevel(from level: Int) -> Double {
        100.0 * Double(level) * (1 + Double(level) * 0.15)
    }

    /// Applies gained XP, returning the resulting (level, experience, didLevelUp).
    static func applyExperience(_ gained: Double, level: Int, experience: Double) -> (level: Int, experience: Double, didLevelUp: Bool) {
        var level = level
        var experience = experience + gained
        var didLevelUp = false
        while experience >= experienceToNextLevel(from: level) {
            experience -= experienceToNextLevel(from: level)
            level += 1
            didLevelUp = true
        }
        return (level, experience, didLevelUp)
    }

    static func isBuildingClassUnlocked(_ buildingClass: BuildingClass, level: Int) -> Bool {
        level >= requiredLevel(for: buildingClass)
    }

    static func requiredLevel(for buildingClass: BuildingClass) -> Int {
        switch buildingClass {
        case .farm: return 1
        case .powerPlant: return 3
        case .dataCenter: return 4
        }
    }
}
