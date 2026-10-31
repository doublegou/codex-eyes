import Foundation

public struct QuotaWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: TimeInterval?
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public var label: String {
        switch windowMinutes {
        case 300: return "5h"
        case 10080: return "Weekly"
        case let n where n % 1440 == 0: return "\(n / 1440)d"
        case let n where n % 60 == 0: return "\(n / 60)h"
        default: return "\(windowMinutes)m"
        }
    }
    public var localizedLabel: String {
        if windowMinutes == 10080 { return L("每周") }
        if windowMinutes % 1440 == 0 { return L("\(windowMinutes / 1440)天") }
        if windowMinutes % 60 == 0 { return L("\(windowMinutes / 60)小时") }
        return L("\(windowMinutes)分钟")
    }
    public init(usedPercent: Double, windowMinutes: Int, resetsAt: TimeInterval? = nil) {
        self.usedPercent = usedPercent; self.windowMinutes = windowMinutes; self.resetsAt = resetsAt
    }
    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent", windowMinutes = "window_minutes", resetsAt = "resets_at"
    }
}

public struct RefreshResult: Codable, Equatable, Sendable {
    public var requested: Bool?
    public var method: String?
    public var status: String?
    public var httpStatus: Int?
    public var errorCode: String?
    public init(status: String? = nil, httpStatus: Int? = nil, method: String? = "api") {
        self.status = status; self.httpStatus = httpStatus; self.method = method; requested = true
    }
    enum CodingKeys: String, CodingKey {
        case requested, method, status, httpStatus = "http_status", errorCode = "error_code"
    }
}

public struct AccountUsage: Codable, Equatable, Sendable {
    public var source: String?
    public var updatedAt: TimeInterval?
    public var primary: QuotaWindow?
    public var secondary: QuotaWindow?
    public var refresh: RefreshResult?
    public var displayWindows: [QuotaWindow] {
        [primary, secondary].compactMap { $0 }.sorted { $0.windowMinutes < $1.windowMinutes }
    }
    public init(source: String? = nil, updatedAt: TimeInterval? = nil, primary: QuotaWindow? = nil,
                secondary: QuotaWindow? = nil, refresh: RefreshResult? = nil) {
        self.source = source; self.updatedAt = updatedAt; self.primary = primary
        self.secondary = secondary; self.refresh = refresh
    }
    enum CodingKeys: String, CodingKey { case source, updatedAt = "updated_at", primary, secondary, refresh }
}

public struct Account: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var email: String?
    public var alias: String?
    public var accountName: String?
    public var profileName: String?
    public var plan: String?
    public var authMode: String?
    public var active: Bool?
    public var usage: AccountUsage?
    /// App-owned timestamp: a successful API check may return an unchanged quota snapshot.
    public var lastConfirmedAt: Date?
    public init(id: String, email: String? = nil, alias: String? = nil, plan: String? = nil,
                usage: AccountUsage? = nil, lastConfirmedAt: Date? = nil, profileName: String? = nil) {
        self.id = id; self.email = email; self.alias = alias; self.plan = plan
        self.usage = usage; self.lastConfirmedAt = lastConfirmedAt
        self.profileName = profileName
    }
    /// Keep the last successful snapshot on failed reads; never borrow another account's quota.
    public func retainingQuota(from previous: Account?) -> Account {
        guard let previous, previous.id == id else { return self }
        var result = self
        let success = usage?.refresh?.status == "ok" && usage?.refresh?.method == "api"
        guard !success else { return result }
        result.lastConfirmedAt = previous.lastConfirmedAt
        let windows = usage?.displayWindows ?? []
        if let cached = previous.usage, !cached.displayWindows.isEmpty,
           windows.isEmpty || (cached.updatedAt ?? 0) >= (usage?.updatedAt ?? 0) {
            let refresh = usage?.refresh ?? RefreshResult(status: "error")
            result.usage = cached
            result.usage?.refresh = refresh
        }
        return result
    }
    public var displayName: String { profileName ?? alias ?? email ?? accountName ?? "Codex" }
    public var recoveryDate: Date? {
        let blocked = [usage?.primary, usage?.secondary].compactMap { $0 }.filter { $0.remaining <= 0 }
        guard !blocked.isEmpty, blocked.allSatisfy({ $0.resetsAt != nil }) else { return nil }
        return blocked.compactMap(\.resetsAt).max().map(Date.init(timeIntervalSince1970:))
    }
    public func availabilitySummary(at now: Date = Date()) -> String {
        switch availability(at: now) {
        case .available: return L("可用")
        case .limited:
            if let date = recoveryDate { return L("\(CompactTime.localizedRemaining(until: date, now: now))后可用") }
            return L("额度已用尽")
        case .loginRequired: return L("需登录")
        case .unknown:
            if usage?.primary == nil && usage?.secondary == nil { return L("暂无额度") }
            return L("待更新")
        }
    }
    public func availability(at now: Date = Date()) -> Availability {
        if usage?.refresh?.status == "missing_auth" || usage?.refresh?.httpStatus == 401 { return .loginRequired }
        if let status = usage?.refresh?.status, !["ok", "not_requested"].contains(status) {
            return .unknown(usage?.refresh?.httpStatus.map { L("访问错误 \($0)") } ?? L("刷新失败 · 显示缓存"))
        }
        guard let confirmed = lastConfirmedAt, now.timeIntervalSince(confirmed) <= 600 else {
            return .unknown(L("待确认 · 数据未更新"))
        }
        let windows = [usage?.primary, usage?.secondary].compactMap { $0 }
        guard !windows.isEmpty else { return .unknown(L("暂无额度信息")) }
        if windows.contains(where: { ($0.resetsAt ?? .greatestFiniteMagnitude) <= now.timeIntervalSince1970 }) {
            return .unknown(L("重置已到 · 等待刷新"))
        }
        if windows.contains(where: { $0.remaining <= 0 }) { return .limited }
        return .available
    }
    enum CodingKeys: String, CodingKey {
        case id = "account_key", email, alias, accountName = "account_name", profileName = "eyes_profile_name", plan
        case authMode = "auth_mode", active, usage, lastConfirmedAt = "eyes_last_confirmed_at"
    }
}

public enum Availability: Equatable, Sendable {
    case available, limited, loginRequired, unknown(String)
    public var text: String {
        switch self {
        case .available: return L("可用")
        case .limited: return L("额度受限")
        case .loginRequired: return L("需要登录")
        case .unknown(let reason): return reason
        }
    }
}

public struct AccountList: Codable, Sendable {
    public var schemaVersion: Int
    public var activeAccountKey: String?
    public var accounts: [Account]
    public init(activeAccountKey: String?, accounts: [Account]) {
        schemaVersion = 1; self.activeAccountKey = activeAccountKey; self.accounts = accounts
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", activeAccountKey = "active_account_key", accounts
    }
}

public struct IdentityState: Equatable, Sendable {
    public var viewedAccountID: String?
    public var configuredAccountID: String?
    public var verifiedRuntimeAccountID: String?
    public init() {}
    public mutating func view(_ id: String) { viewedAccountID = id }
    public mutating func panelOpened() { viewedAccountID = configuredAccountID }
    public mutating func reconcile(_ list: AccountList) {
        configuredAccountID = list.activeAccountKey
        if !list.accounts.contains(where: { $0.id == viewedAccountID }) {
            viewedAccountID = configuredAccountID ?? list.accounts.first?.id
        }
        // A config-file observation does not verify the identity of a running client.
        verifiedRuntimeAccountID = nil
    }
}

public enum DemoData {
    public static func accounts(now: Date = Date()) -> AccountList {
        let t = now.timeIntervalSince1970
        return AccountList(activeAccountKey: "demo-main", accounts: [
            Account(id: "demo-main", email: "alex@example.com", alias: "Alex Chen", plan: "pro",
                    usage: .init(source: "demo", updatedAt: t, primary: .init(usedPercent: 28, windowMinutes: 300, resetsAt: t + 8280),
                                 secondary: .init(usedPercent: 62, windowMinutes: 10080, resetsAt: t + 172800)), lastConfirmedAt: now),
            Account(id: "demo-spare", email: "jamie@example.com", alias: "Jamie Li", plan: "plus",
                    usage: .init(source: "demo", updatedAt: t, primary: .init(usedPercent: 4, windowMinutes: 300, resetsAt: t + 14000),
                                 secondary: .init(usedPercent: 19, windowMinutes: 10080, resetsAt: t + 250000)), lastConfirmedAt: now)
        ])
    }
}

public func compactNumber(_ value: Int) -> String {
    if value >= 1_000_000_000 { return String(format: "%.2fB", Double(value) / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
    return "\(value)"
}
