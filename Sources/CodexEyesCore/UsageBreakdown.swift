import Foundation

/// All shares use the same denominator, including records without a verified account.
public struct UsageBreakdown: Sendable {
    public var total: Int = 0
    public var byAccount: [String: Int] = [:]
    public var unassigned: Int = 0
    public var firstRecordedAt: Date?

    public init(deltas: [UsageDelta], accountKeys: Set<String>, interval: DateInterval? = nil) {
        for delta in deltas {
            guard delta.usage.total > 0 else { continue }
            if let interval, !(delta.date >= interval.start && delta.date < interval.end) { continue }
            total += delta.usage.total
            firstRecordedAt = min(firstRecordedAt ?? delta.date, delta.date)
            if let key = delta.accountKey, accountKeys.contains(key) {
                byAccount[key, default: 0] += delta.usage.total
            } else {
                unassigned += delta.usage.total
            }
        }
    }

    public func fraction(_ amount: Int) -> Double? {
        guard total > 0 else { return nil }
        return Double(amount) / Double(total)
    }
}
