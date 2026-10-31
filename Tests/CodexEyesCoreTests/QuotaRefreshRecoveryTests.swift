import XCTest
import CodexEyesCore

final class QuotaRefreshRecoveryTests: XCTestCase {
    func testTemporaryFailuresRetryButAuthenticationFailuresDoNot() {
        XCTAssertTrue(QuotaRefreshRecovery.shouldRetry(.init(status: "error")))
        XCTAssertTrue(QuotaRefreshRecovery.shouldRetry(.init(status: "http_error", httpStatus: 503)))
        XCTAssertTrue(QuotaRefreshRecovery.shouldRetry(.init(status: "http_error", httpStatus: 429)))
        for result: RefreshResult? in [nil, .init(status: "ok"), .init(status: "not_requested"),
                                       .init(status: "missing_auth"), .init(status: "http_error", httpStatus: 401),
                                       .init(status: "http_error", httpStatus: 403)] {
            XCTAssertFalse(QuotaRefreshRecovery.shouldRetry(result))
        }
    }

    func testFailedRefreshRetainsSnapshotAcrossPersistence() throws {
        let checked = Date(timeIntervalSince1970: 1000)
        let previous = Account(id: "a", usage: .init(updatedAt: 1000,
            primary: .init(usedPercent: 28, windowMinutes: 300),
            secondary: .init(usedPercent: 60, windowMinutes: 10080)), lastConfirmedAt: checked)
        let failed = Account(id: "a", usage: .init(refresh: .init(status: "error")))
        let merged = failed.retainingQuota(from: previous)
        let restored = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(merged))
        XCTAssertEqual(restored.usage?.primary, previous.usage?.primary)
        XCTAssertEqual(restored.usage?.secondary, previous.usage?.secondary)
        XCTAssertEqual(restored.lastConfirmedAt, checked)
        XCTAssertEqual(restored.usage?.updatedAt, 1000)
        XCTAssertEqual(restored.usage?.refresh?.status, "error")
        XCTAssertEqual(restored.availabilitySummary(), "待更新")
        XCTAssertEqual(MenuBarQuota.title(for: restored), "72%")
        XCTAssertTrue(MenuBarQuota.summary(for: restored).contains("上次数据"))
        XCTAssertNil(failed.retainingQuota(from: Account(id: "other", usage: previous.usage)).usage?.primary)
    }

    func testSuccessfulRefreshCanRemoveFiveHourWindow() {
        let previous = Account(id: "a", usage: .init(primary: .init(usedPercent: 28, windowMinutes: 300)))
        let fresh = Account(id: "a", usage: .init(secondary: .init(usedPercent: 20, windowMinutes: 10080),
                                                refresh: .init(status: "ok")))
        let merged = fresh.retainingQuota(from: previous)
        XCTAssertNil(merged.usage?.primary)
        XCTAssertEqual(MenuBarQuota.title(for: merged), "80%")
    }

    func testRetriesBackOffAndStopInsteadOfHammeringService() {
        XCTAssertEqual(QuotaRefreshRecovery.delay(afterFailures: 1, rateLimited: false), 15)
        XCTAssertEqual(QuotaRefreshRecovery.delay(afterFailures: 2, rateLimited: false), 60)
        XCTAssertEqual(QuotaRefreshRecovery.delay(afterFailures: 1, rateLimited: true), 60)
        XCTAssertEqual(QuotaRefreshRecovery.delay(afterFailures: 2, rateLimited: true), 120)
        XCTAssertNil(QuotaRefreshRecovery.delay(afterFailures: 3, rateLimited: false))
        XCTAssertNil(QuotaRefreshRecovery.delay(afterFailures: 0, rateLimited: false))
    }
}
