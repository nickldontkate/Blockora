import XCTest
@testable import Blockora

final class DailyBonusEngineTests: XCTestCase {
    func testFirstEverLoginIsAlwaysAvailable() {
        XCTAssertTrue(DailyBonusEngine.isAvailable(lastClaimDate: nil, now: Date()))
        XCTAssertEqual(DailyBonusEngine.nextStreakDay(currentStreak: 0, lastClaimDate: nil, now: Date()), 1)
    }

    func testNotYetAvailableWithinTheMinimumInterval() {
        let now = Date()
        let claimedRecently = now.addingTimeInterval(-3600) // 1h ago
        XCTAssertFalse(DailyBonusEngine.isAvailable(lastClaimDate: claimedRecently, now: now))
    }

    func testAvailableOnceMinimumIntervalPasses() {
        let now = Date()
        let claimedYesterday = now.addingTimeInterval(-DailyBonusEngine.minimumInterval - 1)
        XCTAssertTrue(DailyBonusEngine.isAvailable(lastClaimDate: claimedYesterday, now: now))
    }

    func testStreakContinuesWithinResetWindow() {
        let now = Date()
        let lastClaim = now.addingTimeInterval(-DailyBonusEngine.minimumInterval - 1)
        XCTAssertEqual(DailyBonusEngine.nextStreakDay(currentStreak: 3, lastClaimDate: lastClaim, now: now), 4)
    }

    func testStreakWrapsAfterFullCycle() {
        let now = Date()
        let lastClaim = now.addingTimeInterval(-DailyBonusEngine.minimumInterval - 1)
        XCTAssertEqual(DailyBonusEngine.nextStreakDay(currentStreak: DailyBonusEngine.cycleLength, lastClaimDate: lastClaim, now: now), 1)
    }

    func testMissingTwoDaysResetsStreak() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-DailyBonusEngine.streakResetThreshold - 1)
        XCTAssertEqual(DailyBonusEngine.nextStreakDay(currentStreak: 5, lastClaimDate: longAgo, now: now), 1)
    }

    func testDaySevenRewardIsTheBigOne() {
        let reward = DailyBonusEngine.reward(forDay: 7)
        XCTAssertEqual(reward[.coins], 1000)
        XCTAssertEqual(reward[.blocks], 20)
    }

    func testEveryCycleDayHasANonEmptyReward() {
        for day in 1...DailyBonusEngine.cycleLength {
            XCTAssertFalse(DailyBonusEngine.reward(forDay: day).isEmpty, "day \(day) should grant something")
        }
    }
}
