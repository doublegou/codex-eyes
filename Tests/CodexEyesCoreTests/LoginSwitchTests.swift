import XCTest
@testable import CodexEyesCore

final class LoginSwitchTests: XCTestCase {
    func testExitedClientRequiresConfirmationByDefault() throws {
        var checks = 0
        XCTAssertTrue(try LoginSwitchPolicy.needsConfirmation(skipConfirmation: false) { checks += 1 })
        XCTAssertEqual(checks, 1)
    }

    func testSuppressionStillChecksExitEveryTime() throws {
        var checks = 0
        for _ in 0..<3 {
            XCTAssertFalse(try LoginSwitchPolicy.needsConfirmation(skipConfirmation: true) { checks += 1 })
        }
        XCTAssertEqual(checks, 3)
    }

    func testRunningOrUnknownClientBlocksEvenWhenConfirmationIsSuppressed() {
        for skip in [false, true] {
            for reason in ["running", "unknown"] {
                XCTAssertThrowsError(try LoginSwitchPolicy.needsConfirmation(skipConfirmation: skip) {
                    throw EyesError.message(reason)
                }) { XCTAssertEqual($0.localizedDescription, reason) }
            }
        }
    }
}
