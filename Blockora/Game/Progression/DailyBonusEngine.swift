import Foundation

/// A classic escalating login-streak reward. Pure and deterministic — no
/// hidden state beyond what's already on `PlayerProfile` — so it's trivially
/// testable and safe to re-evaluate on every launch without side effects.
enum DailyBonusEngine {
    static let cycleLength = 7
    /// A player can claim again once this much real time has passed since
    /// their last claim. Deliberately a bit under 24h (not a strict calendar
    /// day) so a player who logs in slightly earlier each day isn't punished.
    static let minimumInterval: TimeInterval = 20 * 3600
    /// Missing more than this resets the streak back to day 1 instead of
    /// continuing where it left off.
    static let streakResetThreshold: TimeInterval = 48 * 3600

    static func isAvailable(lastClaimDate: Date?, now: Date) -> Bool {
        guard let lastClaimDate else { return true }
        return now.timeIntervalSince(lastClaimDate) >= minimumInterval
    }

    /// The streak day a claim right now would land on (1...cycleLength).
    static func nextStreakDay(currentStreak: Int, lastClaimDate: Date?, now: Date) -> Int {
        guard let lastClaimDate else { return 1 }
        if now.timeIntervalSince(lastClaimDate) > streakResetThreshold { return 1 }
        let next = currentStreak + 1
        return next > cycleLength ? 1 : next
    }

    /// The reward for a given day of the 7-day cycle, escalating toward a
    /// big payout on day 7 before looping back to day 1.
    static func reward(forDay day: Int) -> ResourceBag {
        switch day {
        case 1: return [.coins: 100]
        case 2: return [.coins: 200]
        case 3: return [.blocks: 5]
        case 4: return [.coins: 300, .food: 100]
        case 5: return [.coins: 500, .energy: 100]
        case 6: return [.blocks: 10]
        default: return [.coins: 1000, .blocks: 20]
        }
    }
}
