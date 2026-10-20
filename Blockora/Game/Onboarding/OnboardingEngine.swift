import Foundation

/// A linear, one-shot first-run tutorial (§ new-player onboarding). Each step
/// corresponds to one concrete action the player must take; there is no
/// "skip" — the game just stops nagging once every step has fired, tracked
/// as a single persisted integer on `PlayerProfile` rather than a checklist,
/// since the sequence is fixed and never branches.
enum OnboardingStep: Int, Codable, CaseIterable, Comparable {
    case tapPlot = 0
    case placeFoundation = 1
    case addAnotherModule = 2
    case finishConstruction = 3
    case exploreTabs = 4

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool { lhs.rawValue < rhs.rawValue }

    var message: String {
        switch self {
        case .tapPlot: return "Tap an empty, unlocked plot to start your first building."
        case .placeFoundation: return "Drag a Foundation onto the grid — every building starts with one."
        case .addAnotherModule: return "Drag another module next to it to keep growing your building."
        case .finishConstruction: return "Tap Done when you're happy with your building for now."
        case .exploreTabs: return "Check Contracts, Codex and your World Project down here."
        }
    }

    var iconName: String {
        switch self {
        case .tapPlot: return "hand.tap.fill"
        case .placeFoundation, .addAnotherModule: return "hand.draw.fill"
        case .finishConstruction: return "checkmark.circle.fill"
        case .exploreTabs: return "square.grid.2x2.fill"
        }
    }

    /// Steps whose hint belongs inside Construction Mode's own chrome rather
    /// than floating over the city overview.
    static let constructionSteps: Set<OnboardingStep> = [.placeFoundation, .addAnotherModule, .finishConstruction]
}

/// Pure progression rules over the single persisted `onboardingStep` integer.
/// Kept as plain `Int?` on `PlayerProfile` (not `OnboardingStep?`) for the
/// same backward-compatibility reason as `dailyBonusStreak`: an unrecognized
/// future raw value must still decode instead of resetting the save.
enum OnboardingEngine {
    /// Moves past `trigger` only if that's exactly where the player currently
    /// is — already being past it (or not there yet) leaves it untouched, so
    /// firing a hook out of order or more than once is always harmless.
    static func advance(current: Int?, ifAt trigger: OnboardingStep) -> Int? {
        guard current == trigger.rawValue else { return current }
        return trigger.rawValue + 1
    }

    static func step(fromRaw raw: Int?) -> OnboardingStep? {
        guard let raw else { return nil }
        return OnboardingStep(rawValue: raw)
    }

    /// A save from before onboarding existed gets backfilled once: a
    /// brand-new city (no buildings yet) starts the tutorial from the top;
    /// an already-established city is treated as long past needing it.
    static func initialValue(hasExistingBuildings: Bool) -> Int {
        hasExistingBuildings ? OnboardingStep.allCases.count : OnboardingStep.tapPlot.rawValue
    }
}
