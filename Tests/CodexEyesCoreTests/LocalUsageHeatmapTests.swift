import XCTest
@testable import CodexEyesCore

final class LocalUsageHeatmapTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func snapshot(_ rows: [(Date, Int)]) -> LocalSnapshot {
        .init(sessions: [], deltas: rows.enumerated().map { index, row in
            .init(id: String(index), sessionID: "test", date: row.0, usage: .init(total: row.1))
        }, warnings: [])
    }
    func testRollingRangesRespectLocalDaysAndIncludeEmptyDates() {
        let now = date(2026, 3, 10, 12)
        let source = snapshot([(date(2026, 2, 9), 1), (date(2026, 2, 10), 2),
                               (date(2026, 3, 3, 23), 4), (date(2026, 3, 4), 8),
                               (date(2026, 3, 8), 16), (now, 32), (date(2026, 3, 11), 64)])
        let seven = LocalUsageHeatmap(snapshot: source, range: .sevenDays, now: now, calendar: calendar)
        XCTAssertEqual(seven.cells.count, 7)
        XCTAssertEqual(seven.cells.first?.start, date(2026, 3, 4))
        XCTAssertEqual(seven.cells.last?.end, date(2026, 3, 11))
        XCTAssertEqual(seven.total, 56)
        XCTAssertEqual(seven.cells.map(\.tokens), [8, 0, 0, 0, 16, 0, 32])
        // The DST transition is a 23-hour day, still exactly one cell.
        XCTAssertEqual(seven.cells[4].end.timeIntervalSince(seven.cells[4].start), 23 * 3600)
        let thirty = LocalUsageHeatmap(snapshot: source, range: .thirtyDays, now: now, calendar: calendar)
        XCTAssertEqual(thirty.cells.count, 30)
        XCTAssertEqual(thirty.cells.first?.start, date(2026, 2, 9))
        XCTAssertEqual(thirty.total, 63)
    }
    func testAllKeepsFullHistoryWhenCoarsenedToWeeksMonthsOrYears() {
        let now = date(2026, 10, 29, 12)
        for (oldest, expectedUnit) in [(date(2025, 1, 1), LocalUsageHeatmap.Unit.week),
                                       (date(2000, 1, 1), .month), (date(1970, 1, 1), .year)] {
            let result = LocalUsageHeatmap(snapshot: snapshot([(oldest, 17), (now, 23)]),
                                          range: .all, now: now, calendar: calendar)
            XCTAssertEqual(result.unit, expectedUnit)
            XCTAssertLessThanOrEqual(result.cells.count, 336)
            XCTAssertLessThanOrEqual(result.cells.first!.start, oldest)
            XCTAssertEqual(result.cells.last?.end, date(2026, 10, 30))
            XCTAssertEqual(result.total, 40)
            XCTAssertEqual(result.cells.reduce(0) { $0 + $1.tokens }, 40)
        }
    }
    func testFullDailyHistoryKeepsEveryDateWithoutCoarsening() {
        let oldest = date(2025, 1, 1), now = date(2026, 10, 29, 12)
        let result = LocalUsageHeatmap(snapshot: snapshot([(oldest, 17), (now, 23)]),
                                      range: .all, now: now, calendar: calendar, coarsenLongHistory: false)
        let expected = calendar.dateComponents([.day], from: oldest, to: calendar.startOfDay(for: now)).day! + 1
        XCTAssertEqual(result.unit, .day)
        XCTAssertEqual(result.cells.count, expected)
        XCTAssertEqual(result.cells.first?.tokens, 17)
        XCTAssertEqual(result.cells.last?.tokens, 23)
        XCTAssertTrue(result.cells.dropFirst().dropLast().allSatisfy { $0.tokens == 0 })
        XCTAssertEqual(result.total, 40)
        XCTAssertEqual(result.cells.last?.end, date(2026, 10, 30))
    }
    func testDailyBucketsSumMultipleRecordsAndIntensityHasFourLevels() {
        let now = date(2026, 10, 29, 12)
        let result = LocalUsageHeatmap(snapshot: snapshot([(date(2026, 10, 28), 5), (date(2026, 10, 28, 1), 20),
                                                         (now, 100)]), range: .sevenDays, now: now, calendar: calendar)
        XCTAssertEqual(result.total, 125)
        XCTAssertEqual(result.cells[5].tokens, 25)
        XCTAssertEqual(result.level(for: result.cells[0]), 0)
        XCTAssertEqual(result.level(for: result.cells[5]), 2)
        XCTAssertEqual(result.level(for: result.cells[6]), 4)
    }
    func testEmptyHistoryAndFutureRecordsDoNotProduceFakeActivity() {
        let now = date(2026, 10, 29, 12)
        let source = snapshot([(date(2026, 10, 30), 100), (now, 0)])
        let all = LocalUsageHeatmap(snapshot: source, range: .all, now: now, calendar: calendar)
        XCTAssertTrue(all.cells.isEmpty)
        XCTAssertEqual(all.total, 0)
        let seven = LocalUsageHeatmap(snapshot: source, range: .sevenDays, now: now, calendar: calendar)
        XCTAssertEqual(seven.cells.count, 7)
        XCTAssertTrue(seven.cells.allSatisfy { seven.level(for: $0) == 0 })
    }
}
