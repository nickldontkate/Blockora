import XCTest
@testable import Blockora

final class WorldEventEngineTests: XCTestCase {
    func testActiveEventsExcludesExpiredAndFutureOnes() {
        let now = Date()
        let past = WorldEvent(id: UUID(), title: "Past", flavorText: "", resourceModifiers: [:], startDate: now.addingTimeInterval(-7200), endDate: now.addingTimeInterval(-3600))
        let current = WorldEvent(id: UUID(), title: "Current", flavorText: "", resourceModifiers: [:], startDate: now.addingTimeInterval(-60), endDate: now.addingTimeInterval(3600))
        let future = WorldEvent(id: UUID(), title: "Future", flavorText: "", resourceModifiers: [:], startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200))

        let active = WorldEventEngine.activeEvents([past, current, future], at: now)
        XCTAssertEqual(active.map(\.id), [current.id])
    }

    func testCombinedModifiersCompoundMultiplicatively() {
        let now = Date()
        let first = WorldEvent(id: UUID(), title: "A", flavorText: "", resourceModifiers: [.data: 1.5], startDate: now, endDate: now.addingTimeInterval(3600))
        let second = WorldEvent(id: UUID(), title: "B", flavorText: "", resourceModifiers: [.data: 2.0], startDate: now, endDate: now.addingTimeInterval(3600))

        let combined = WorldEventEngine.combinedModifiers([first, second], at: now)
        XCTAssertEqual(combined[.data] ?? 0, 3.0, accuracy: 0.001)
    }

    func testRandomEventIsAlwaysActiveAtItsOwnStartDate() {
        let start = Date()
        let event = WorldEventEngine.randomEvent(starting: start)
        XCTAssertTrue(event.isActive(at: start))
        XCTAssertGreaterThan(event.endDate, event.startDate)
    }
}
