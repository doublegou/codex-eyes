import Foundation

public enum MenuBarQuota {
    public static func window(for account: Account?) -> QuotaWindow? {
        let windows = account?.usage?.displayWindows ?? []
        return windows.first { $0.windowMinutes == 300 } ?? windows.first { $0.windowMinutes == 10080 }
    }

    public static func title(for account: Account?, now: Date = Date()) -> String {
        guard let account, let window = window(for: account) else { return "—" }
        switch account.availability(at: now) {
        case .available, .limited: return "\(Int(window.remaining.rounded()))%"
        default: return "—"
        }
    }

    public static func summary(for account: Account?, now: Date = Date()) -> String {
        guard let account else { return L("暂无额度数据") }
        guard title(for: account, now: now) != "—", let window = window(for: account) else {
            return account.availability(at: now).text
        }
        return L("\(window.localizedLabel)剩余 \(title(for: account, now: now))")
    }
}
