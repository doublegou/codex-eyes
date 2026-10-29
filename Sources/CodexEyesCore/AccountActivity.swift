import Foundation

public struct AccountActivitySummary: Codable, Equatable, Sendable {
    public var lifetimeTokens: Int?
    public var peakDailyTokens: Int?
    public var longestRunningTurnSec: Int?
    public var currentStreakDays: Int?
    public var longestStreakDays: Int?
    public init(lifetimeTokens: Int? = nil, peakDailyTokens: Int? = nil) {
        self.lifetimeTokens = lifetimeTokens; self.peakDailyTokens = peakDailyTokens
    }
}

public struct AccountActivityDay: Codable, Equatable, Identifiable, Sendable {
    public var startDate: String
    public var tokens: Int
    public var id: String { startDate }
    public init(startDate: String, tokens: Int) { self.startDate = startDate; self.tokens = tokens }
}

/// Allowlisted service fields only. Local logs and credentials never enter this cache.
public struct AccountActivity: Codable, Equatable, Sendable {
    public var summary: AccountActivitySummary
    public var dailyUsageBuckets: [AccountActivityDay]?
    public var fetchedAt: Date
    public var latestDay: String? { dailyUsageBuckets?.map(\.startDate).max() }
    public init(summary: AccountActivitySummary, dailyUsageBuckets: [AccountActivityDay]? = nil, fetchedAt: Date = Date()) {
        self.summary = summary; self.dailyUsageBuckets = dailyUsageBuckets; self.fetchedAt = fetchedAt
    }
    public static func decodeReply(_ data: Data, fetchedAt: Date = Date()) throws -> AccountActivity {
        struct Reply: Decodable { var summary: AccountActivitySummary; var dailyUsageBuckets: [AccountActivityDay]? }
        let reply: Reply
        do { reply = try JSONDecoder().decode(Reply.self, from: data) }
        catch { throw EyesError.message(L("账号统计返回格式不兼容。")) }
        let counters = [reply.summary.lifetimeTokens, reply.summary.peakDailyTokens, reply.summary.longestRunningTurnSec,
                        reply.summary.currentStreakDays, reply.summary.longestStreakDays].compactMap { $0 }
        guard counters.allSatisfy({ $0 >= 0 }), (reply.dailyUsageBuckets?.count ?? 0) <= 10000 else {
            throw EyesError.message(L("账号统计数值无效。"))
        }
        var merged: [String: Int] = [:]
        if let buckets = reply.dailyUsageBuckets {
            for day in buckets {
                guard dayDate(day.startDate) != nil, day.tokens >= 0 else { throw EyesError.message(L("账号每日统计格式无效。")) }
                let sum = (merged[day.startDate] ?? 0).addingReportingOverflow(day.tokens)
                guard !sum.overflow else { throw EyesError.message(L("账号每日统计数值超出范围。")) }
                merged[day.startDate] = sum.partialValue
            }
        }
        let days = reply.dailyUsageBuckets.map { _ in merged.keys.sorted().map { AccountActivityDay(startDate: $0, tokens: merged[$0]!) } }
        return .init(summary: reply.summary, dailyUsageBuckets: days, fetchedAt: fetchedAt)
    }
    static func dayDate(_ text: String) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              text.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), year >= 2000 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year && actual.month == month && actual.day == day else { return nil }
        return date
    }
}

public struct AccountActivityState: Codable, Equatable, Sendable {
    public var snapshot: AccountActivity?
    public var error: String?
    public init(snapshot: AccountActivity? = nil, error: String? = nil) { self.snapshot = snapshot; self.error = error }
    public func isCached(at now: Date = Date()) -> Bool {
        guard let snapshot else { return false }
        return error != nil || now.timeIntervalSince(snapshot.fetchedAt) > 900
    }
}

/// Shares are available only when every displayed account supplied a lifetime value.
public struct AccountActivityTotals: Sendable {
    public let amounts: [String: Int]
    public let total: Int?
    public let complete: Bool
    public let cached: Bool
    public init(accountIDs: [String], states: [String: AccountActivityState], now: Date = Date()) {
        let keys = Set(accountIDs)
        var amounts: [String: Int] = [:]; var sum = 0; var overflow = false
        for key in keys {
            if let value = states[key]?.snapshot?.summary.lifetimeTokens, value >= 0 {
                amounts[key] = value
                let addition = sum.addingReportingOverflow(value); sum = addition.partialValue; overflow = overflow || addition.overflow
            }
        }
        self.amounts = amounts
        complete = !keys.isEmpty && amounts.count == keys.count && !overflow
        total = amounts.isEmpty || overflow ? nil : sum
        cached = keys.contains { states[$0]?.isCached(at: now) == true }
    }
    public func fraction(for id: String) -> Double? {
        guard complete, let total, total > 0, let value = amounts[id] else { return nil }
        return Double(value) / Double(total)
    }
}
