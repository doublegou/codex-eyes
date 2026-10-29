import Foundation

/// One local calendar day, with shares only when its input/output records reconcile to the total.
public struct DailyTokenComposition: Sendable {
    public let total: Int
    public let input: Int?
    public let output: Int?
    public init(snapshot: LocalSnapshot, date: Date = Date(), calendar: Calendar = .current) {
        let interval = calendar.dateInterval(of: .day, for: date)
        let records = snapshot.deltas.filter {
            guard let interval else { return false }
            return $0.date >= interval.start && $0.date < interval.end && $0.usage.total > 0
        }
        total = records.reduce(0) { $0 + $1.usage.total }
        let complete = records.allSatisfy {
            let sum = $0.usage.input.addingReportingOverflow($0.usage.output)
            return !sum.overflow && $0.usage.input >= 0 && $0.usage.output >= 0 && sum.partialValue == $0.usage.total
        }
        input = complete ? records.reduce(0) { $0 + $1.usage.input } : nil
        output = complete ? records.reduce(0) { $0 + $1.usage.output } : nil
    }
    public func fraction(_ amount: Int?) -> Double? {
        guard total > 0, let amount else { return nil }
        return Double(amount) / Double(total)
    }
}
