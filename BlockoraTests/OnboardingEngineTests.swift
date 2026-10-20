import XCTest
@testable import Blockora

final class OnboardingEngineTests: XCTestCase {
    func testAdvancesOnlyWhenCurrentlyAtTheTrigger() {
        XCTAssertEqual(OnboardingEngine.advance(current: OnboardingStep.tapPlot.rawValue, ifAt: .tapPlot), OnboardingStep.placeFoundation.rawValue)
    }

    func testDoesNotAdvanceWhenNotAtTheTrigger() {
        XCTAssertEqual(OnboardingEngine.advance(current: OnboardingStep.placeFoundation.rawValue, ifAt: .tapPlot), OnboardingStep.placeFoundation.rawValue)
    }

    func testDoesNotAdvanceOnceAlreadyPastEveryStep() {
        let done = OnboardingStep.allCases.count
        XCTAssertEqual(OnboardingEngine.advance(current: done, ifAt: .exploreTabs), done)
    }

    func testAdvancingPastTheFinalStepYieldsNoActiveStep() {
        let afterExploreTabs = OnboardingEngine.advance(current: OnboardingStep.exploreTabs.rawValue, ifAt: .exploreTabs)
        XCTAssertNil(OnboardingEngine.step(fromRaw: afterExploreTabs))
    }

    func testNilRawValueMeansNoActiveStep() {
        XCTAssertNil(OnboardingEngine.step(fromRaw: nil))
    }

    func testUnrecognizedFutureRawValueDecodesAsNoActiveStepRatherThanCrashing() {
        XCTAssertNil(OnboardingEngine.step(fromRaw: 999))
    }

    func testInitialValueStartsFromTheTopForABrandNewCity() {
        XCTAssertEqual(OnboardingEngine.initialValue(hasExistingBuildings: false), OnboardingStep.tapPlot.rawValue)
    }

    func testInitialValueSkipsTheTutorialForAnAlreadyEstablishedCity() {
        XCTAssertNil(OnboardingEngine.step(fromRaw: OnboardingEngine.initialValue(hasExistingBuildings: true)))
    }
}
