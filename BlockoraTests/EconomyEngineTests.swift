import XCTest
@testable import Blockora

final class EconomyEngineTests: XCTestCase {
    func testContractCannotCompleteWithoutEnoughResources() {
        var contract = EconomyEngine.starterContracts()[0]
        contract.status = .accepted
        contract.acceptedAt = Date()

        XCTAssertFalse(EconomyEngine.canComplete(contract, playerResources: [.food: 50]))
        XCTAssertNil(EconomyEngine.complete(contract, playerResources: [.food: 50]))
    }

    func testContractCompletionDeductsCostAndGrantsReward() {
        var contract = EconomyEngine.starterContracts()[0] // Deliver 100 Food -> 400 coins
        contract.status = .accepted
        contract.acceptedAt = Date()

        let result = EconomyEngine.complete(contract, playerResources: [.food: 150, .coins: 20])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.resources[.food] ?? -1, 50, accuracy: 0.01)
        XCTAssertEqual(result?.resources[.coins] ?? -1, 420, accuracy: 0.01)
        XCTAssertEqual(result?.reward[.coins] ?? 0, 400, accuracy: 0.01)
    }

    func testContractRequiresAcceptedStatus() {
        let contract = EconomyEngine.starterContracts()[0] // still .available
        XCTAssertFalse(EconomyEngine.canComplete(contract, playerResources: [.food: 1000]))
    }

    func testProgressionLevelsUpAndCarriesRemainderXP() {
        let requiredForLevel1 = ProgressionEngine.experienceToNextLevel(from: 1)
        let result = ProgressionEngine.applyExperience(requiredForLevel1 + 25, level: 1, experience: 0)
        XCTAssertEqual(result.level, 2)
        XCTAssertEqual(result.experience, 25, accuracy: 0.01)
        XCTAssertTrue(result.didLevelUp)
    }
}
