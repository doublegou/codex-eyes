import Foundation

public enum QuotaRefreshRecovery {
    /// Only read queries retry. Authentication failures require user attention.
    public static func shouldRetry(_ result: RefreshResult?) -> Bool {
        guard let result, let status = result.status,
              !["ok", "not_requested", "missing_auth"].contains(status),
              ![401, 403].contains(result.httpStatus ?? 0) else { return false }
        return true
    }

    public static func delay(afterFailures count: Int, rateLimited: Bool) -> TimeInterval? {
        guard (1...2).contains(count) else { return nil }
        return rateLimited ? 60 * Double(count) : (count == 1 ? 15 : 60)
    }
}
