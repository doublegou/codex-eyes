import XCTest
@testable import CodexEyesCore

final class AccountActivityHeatmapTests: XCTestCase {
    func testAllRecordsSurviveAcrossYearsWithoutThirtyDayCutoff() throws {
        let snapshot = try AccountActivity.decodeReply(Data(#"{"summary":{},"dailyUsageBuckets":[{"startDate":"2025-12-31","tokens":50},{"startDate":"2026-03-05","tokens":100},{"startDate":"2026-03-05","tokens":25}]}"#.utf8))
        let heatmap = AccountActivityHeatmap(days: snapshot.dailyUsageBuckets!)
        let days = heatmap.weeks.flatMap(\.days).compactMap { $0 }
        XCTAssertEqual(days.first?.date, "2025-12-31")
        XCTAssertEqual(days.last?.date, "2026-03-05")
        XCTAssertEqual(days.compactMap(\.tokens).reduce(0, +), 175)
        XCTAssertEqual(days.filter { $0.tokens != nil }.count, 2)
        XCTAssertTrue(heatmap.weeks.allSatisfy { $0.days.count == 7 })
        XCTAssertEqual(heatmap.peak, 125)
    }
    func testServerDatesKeepMondayRowsAndLeapDayWithoutInventingZeroes() {
        let heatmap = AccountActivityHeatmap(days: [.init(startDate: "2024-02-28", tokens: 0), .init(startDate: "2024-03-01", tokens: 20)])
        XCTAssertEqual(heatmap.weeks.count, 1)
        let week = heatmap.weeks[0].days
        XCTAssertNil(week[0]); XCTAssertNil(week[1]) // Monday and Tuesday precede the returned range.
        XCTAssertEqual(week[2]?.date, "2024-02-28"); XCTAssertEqual(week[2]?.tokens, 0)
        XCTAssertEqual(week[3]?.date, "2024-02-29"); XCTAssertNil(week[3]?.tokens)
        XCTAssertEqual(week[4]?.date, "2024-03-01")
        XCTAssertNil(week[5]); XCTAssertNil(week[6])
        XCTAssertEqual(heatmap.level(for: week[2]!), 0)
        XCTAssertEqual(heatmap.level(for: week[3]!), 0)
        XCTAssertEqual(heatmap.level(for: week[4]!), 4)
    }
    func testShortHistoryDoesNotAddMonthsOfEmptyDates() {
        let days = AccountActivityHeatmap(days: [.init(startDate: "2026-08-27", tokens: 10),
                                                .init(startDate: "2026-10-30", tokens: 20)])
            .weeks.flatMap(\.days).compactMap { $0 }
        XCTAssertEqual(days.count, 65)
        XCTAssertEqual(days.first?.date, "2026-08-27")
        XCTAssertEqual(days.last?.date, "2026-10-30")
        XCTAssertEqual(days.compactMap(\.tokens).reduce(0, +), 30)
        XCTAssertTrue(days.dropFirst().dropLast().allSatisfy { $0.tokens == nil })
    }
    func testShortHistoryContextIsBoundedToSixWeeksAndNeverAddsUsage() {
        let source = [AccountActivityDay(startDate: "2026-08-27", tokens: 10), .init(startDate: "2026-10-30", tokens: 20)]
        let actual = AccountActivityHeatmap(days: source)
        let padded = AccountActivityHeatmap(days: source, contextWeeks: 99)
        XCTAssertEqual(padded.weeks.count, actual.weeks.count + 6)
        XCTAssertEqual(padded.weeks.flatMap(\.days).compactMap { $0?.tokens }.reduce(0, +), 30)
        XCTAssertTrue(padded.weeks.prefix(6).flatMap(\.days).allSatisfy { $0?.tokens == nil })
        XCTAssertEqual(AccountActivityHeatmap(days: source, contextWeeks: -1).weeks.count, actual.weeks.count)
        XCTAssertTrue(AccountActivityHeatmap(days: [], contextWeeks: 6).weeks.isEmpty)
    }
    func testSundayRemainsLastRowAndEmptyOrInvalidRecordsDoNotCreateCells() {
        XCTAssertTrue(AccountActivityHeatmap(days: []).weeks.isEmpty)
        XCTAssertTrue(AccountActivityHeatmap(days: [.init(startDate: "2026-02-30", tokens: 1)]).weeks.isEmpty)
        let heatmap = AccountActivityHeatmap(days: [.init(startDate: "2026-10-25", tokens: 1)])
        XCTAssertEqual(heatmap.weeks.count, 1)
        XCTAssertEqual(heatmap.weeks[0].days[6]?.date, "2026-10-25")
        XCTAssertTrue(heatmap.weeks[0].days.prefix(6).allSatisfy { $0 == nil })
    }
}
