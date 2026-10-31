import Foundation

public enum MenuBarQuota {
    public static func window(for account: Account?) -> QuotaWindow? {
        let windows = account?.usage?.displayWindows ?? []
        return windows.first { $0.windowMinutes == 300 } ?? windows.first { $0.windowMinutes == 10080 }
    }

    public static func title(for account: Account?, now: Date = Date()) -> String {
        guard let window = window(for: account) else { return "—" }
        return "\(Int(window.remaining.rounded()))%"
    }

    public static func summary(for account: Account?, now: Date = Date()) -> String {
        guard let account else { return L("暂无额度数据") }
        guard title(for: account, now: now) != "—", let window = window(for: account) else {
            return account.availability(at: now).text
        }
        let quota = L("\(window.localizedLabel)剩余 \(title(for: account, now: now))")
        switch account.availability(at: now) {
        case .available, .limited: return quota
        default: return quota + " · " + L("上次数据") + " · " + account.availabilitySummary(at: now)
        }
    }
}
