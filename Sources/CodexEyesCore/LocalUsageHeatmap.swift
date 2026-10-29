import Foundation

public enum UsageHistoryRange: String, CaseIterable, Sendable {
    case sevenDays, thirtyDays, all
    public var label: String {
        switch self { case .sevenDays: return L("7天"); case .thirtyDays: return L("30天"); case .all: return L("全部") }
    }
}

public struct UsageHeatmapCell: Identifiable, Sendable {
    public let start: Date
    public let end: Date
    public let tokens: Int
    public var id: Date { start }
}

/// Local calendar buckets. Long histories coarsen to weeks/months/years rather than discarding records.
public struct LocalUsageHeatmap: Sendable {
    public enum Unit: Sendable { case day, week, month, year }
    public let cells: [UsageHeatmapCell]
    public let total: Int
    public let unit: Unit
    public var peak: Int { cells.map(\.tokens).max() ?? 0 }
    public init(snapshot: LocalSnapshot, range: UsageHistoryRange, now: Date = Date(), calendar: Calendar = .current, coarsenLongHistory: Bool = true) {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        let eligible = snapshot.deltas.filter { $0.date >= Date(timeIntervalSince1970: 0) && $0.date < end && $0.usage.total > 0 }
        let oldest = eligible.map(\.date).min().map { calendar.startOfDay(for: $0) }
        let start: Date
        let component: Calendar.Component
        switch range {
        case .sevenDays:
            start = calendar.date(byAdding: .day, value: -6, to: today)!; component = .day; unit = .day
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -29, to: today)!; component = .day; unit = .day
        case .all:
            guard let oldest else { cells = []; total = 0; unit = .day; return }
            func count(_ component: Calendar.Component) -> Int {
                let first = calendar.dateInterval(of: component, for: oldest)!.start
                let last = calendar.dateInterval(of: component, for: today)!.start
                return (calendar.dateComponents([component], from: first, to: last).value(for: component) ?? 0) + 1
            }
            if !coarsenLongHistory || count(.day) <= 336 { component = .day; unit = .day }
            else if count(.weekOfYear) <= 336 { component = .weekOfYear; unit = .week }
            else if count(.month) <= 336 { component = .month; unit = .month }
            else { component = .year; unit = .year }
            start = calendar.dateInterval(of: component, for: oldest)!.start
        }
        var totals: [Date: Int] = [:]
        for record in eligible where record.date >= start {
            let bucket = calendar.dateInterval(of: component, for: record.date)!.start
            totals[bucket, default: 0] += record.usage.total
        }
        var result: [UsageHeatmapCell] = [], cursor = start
        while cursor < end {
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            result.append(.init(start: cursor, end: min(next, end), tokens: totals[cursor] ?? 0))
            cursor = next
        }
        cells = result; total = result.reduce(0) { $0 + $1.tokens }
    }
    public func level(for cell: UsageHeatmapCell) -> Int {
        guard cell.tokens > 0, peak > 0 else { return 0 }
        return min(4, max(1, Int(ceil(sqrt(Double(cell.tokens) / Double(peak)) * 4))))
    }
}
