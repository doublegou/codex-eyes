import XCTest
@testable import CodexEyesCore

final class DailyTokenCompositionTests: XCTestCase {
    func testTodayInputOutputSharesMatchTotalAndDoNotAddCachedOrReasoningAgain() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let rows = [
            UsageDelta(id: "old", sessionID: "one", date: day.addingTimeInterval(-1), usage: .init(input: 90, output: 9, total: 99)),
            UsageDelta(id: "one", sessionID: "one", date: day, usage: .init(input: 80, cached: 70, output: 20, reasoning: 10, total: 100)),
            UsageDelta(id: "two", sessionID: "two", date: day.addingTimeInterval(1), usage: .init(input: 40, output: 10, total: 50)),
            UsageDelta(id: "next", sessionID: "two", date: day.addingTimeInterval(86400), usage: .init(input: 100, total: 100))
        ]
        let snapshot = LocalSnapshot(sessions: [], deltas: rows, warnings: [])
        let composition = DailyTokenComposition(snapshot: snapshot, date: day, calendar: calendar)
        XCTAssertEqual(composition.total, snapshot.daily(day, calendar: calendar))
        XCTAssertEqual(composition.total, 150)
        XCTAssertEqual(composition.input, 120)
        XCTAssertEqual(composition.output, 30)
        XCTAssertEqual(composition.fraction(composition.input), 0.8)
        XCTAssertEqual(composition.fraction(composition.output), 0.2)
    }
    func testMissingOrInconsistentComponentsRemainUnknownAndZeroDayHasNoPercentage() {
        let now = Date()
        for usage in [TokenUsage(total: 100), TokenUsage(input: 20, output: 10, total: 35), TokenUsage(input: Int.max, output: 1, total: 10)] {
            let snapshot = LocalSnapshot(sessions: [], deltas: [.init(id: "one", sessionID: "one", date: now, usage: usage)], warnings: [])
            let composition = DailyTokenComposition(snapshot: snapshot, date: now)
            XCTAssertEqual(composition.total, usage.total)
            XCTAssertNil(composition.input); XCTAssertNil(composition.output)
            XCTAssertNil(composition.fraction(composition.input))
        }
        let empty = DailyTokenComposition(snapshot: .init(sessions: [], deltas: [], warnings: []), date: now)
        XCTAssertEqual(empty.total, 0); XCTAssertEqual(empty.input, 0); XCTAssertEqual(empty.output, 0)
        XCTAssertNil(empty.fraction(0))
    }
}
