import Foundation
import CoreGraphics

/// Calendar-aligned service dates, independent of the Mac's time zone. Missing buckets stay unknown.
public struct AccountActivityHeatmap: Sendable {
    public struct Day: Identifiable, Sendable {
        public let date: String
        public let calendarDate: Date
        public let tokens: Int?
        public var id: String { date }
    }
    public struct Week: Identifiable, Sendable {
        public let id: Date
        public let days: [Day?] // Monday through Sunday; leading and trailing padding is not a date.
    }
    public let weeks: [Week]
    public let peak: Int

    /// The account snapshot has already normalized duplicate service buckets.
    public init(days: [AccountActivityDay], contextWeeks: Int = 0) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        var records: [Date: AccountActivityDay] = [:]
        for day in days where day.tokens >= 0 {
            if let date = AccountActivity.dayDate(day.startDate) { records[date] = day }
        }
        peak = records.values.map(\.tokens).max() ?? 0
        guard let firstRecord = records.keys.min(), let last = records.keys.max() else { weeks = []; return }
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstRecord)!.start
        let extraWeeks = min(6, max(0, contextWeeks))
        let first = extraWeeks == 0 ? firstRecord : calendar.date(byAdding: .day, value: -7 * extraWeeks, to: firstWeek)!
        var cursor = calendar.dateInterval(of: .weekOfYear, for: first)!.start
        var result: [Week] = []
        while cursor <= last {
            let weekStart = cursor
            var cells: [Day?] = []
            for _ in 0..<7 {
                if cursor < first || cursor > last { cells.append(nil) }
                else {
                    let parts = calendar.dateComponents([.year, .month, .day], from: cursor)
                    let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
                    cells.append(Day(date: key, calendarDate: cursor, tokens: records[cursor]?.tokens))
                }
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            }
            result.append(Week(id: weekStart, days: cells))
        }
        weeks = result
    }
    public func level(for day: Day) -> Int {
        guard let tokens = day.tokens, tokens > 0, peak > 0 else { return 0 }
        return min(4, max(1, Int(ceil(sqrt(Double(tokens) / Double(peak)) * 4))))
    }
}

/// Shared drawing and hit-testing geometry: tooltip targets use exactly the grid's coordinates.
public struct AccountHeatmapLayout {
    public struct CellIndex: Equatable { public let column: Int; public let row: Int }
    public let columns: Int
    public let gap: CGFloat = 4
    public let side: CGFloat
    public var pitch: CGFloat { side + gap }
    public var width: CGFloat { CGFloat(columns) * pitch - gap }
    public var gridHeight: CGFloat { 7 * side + 6 * gap }
    public var height: CGFloat { gridHeight + 26 }
    public init(columns: Int, availableWidth: CGFloat) {
        self.columns = max(1, columns)
        side = min(20, max(8, (max(1, availableWidth) - CGFloat(self.columns - 1) * gap) / CGFloat(self.columns)))
    }
    public func rect(column: Int, row: Int) -> CGRect {
        CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: side, height: side)
    }
    public func cell(at point: CGPoint) -> CellIndex? {
        guard point.x >= 0, point.y >= 0, point.x < width, point.y < gridHeight else { return nil }
        return CellIndex(column: min(columns - 1, Int((point.x + gap / 2) / pitch)),
                         row: min(6, Int((point.y + gap / 2) / pitch)))
    }
}
