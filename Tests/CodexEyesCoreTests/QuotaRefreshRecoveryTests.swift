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

    func testRetriesBackOffAndStopInsteadOfHammeringService() {
        XCTAssertEqual(QuotaRefreshRecovery.delay(afterFailures: 1, rateLimited: false), 15)
        XCTAssertEqual(QuotaRefreshRecovery.delay(afterFailures: 2, rateLimited: false), 60)
        XCTAssertEqual(QuotaRefreshRecovery.delay(afterFailures: 1, rateLimited: true), 60)
        XCTAssertEqual(QuotaRefreshRecovery.delay(afterFailures: 2, rateLimited: true), 120)
        XCTAssertNil(QuotaRefreshRecovery.delay(afterFailures: 3, rateLimited: false))
        XCTAssertNil(QuotaRefreshRecovery.delay(afterFailures: 0, rateLimited: false))
    }
}
