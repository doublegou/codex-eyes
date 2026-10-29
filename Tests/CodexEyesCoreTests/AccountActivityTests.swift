import XCTest
@testable import CodexEyesCore

final class AccountActivityTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexEyesActivityTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testNullableFieldsRemainUnknownAndOnlyAllowlistedDataIsCached() throws {
        let data = Data(#"{"summary":{"lifetimeTokens":null,"peakDailyTokens":0,"future":"x"},"dailyUsageBuckets":null,"accessToken":"PRIVATE-TOKEN","threadUsage":{"secret":"PRIVATE"}}"#.utf8)
        let activity = try AccountActivity.decodeReply(data)
        XCTAssertNil(activity.summary.lifetimeTokens)
        XCTAssertEqual(activity.summary.peakDailyTokens, 0)
        XCTAssertNil(activity.dailyUsageBuckets)
        let encoded = String(decoding: try JSONEncoder().encode(activity), as: UTF8.self)
        XCTAssertFalse(encoded.contains("PRIVATE"))
        let empty = try AccountActivity.decodeReply(Data(#"{"summary":{"lifetimeTokens":0},"dailyUsageBuckets":[]}"#.utf8))
        XCTAssertEqual(empty.dailyUsageBuckets, [])
    }
    func testDailyDatesArePreservedMergedAndSortedWithoutTimezoneRebucketing() throws {
        let json = #"{"summary":{"lifetimeTokens":42},"dailyUsageBuckets":[{"startDate":"2026-10-29","tokens":12},{"startDate":"2026-10-27","tokens":20},{"startDate":"2026-10-29","tokens":10}]}"#
        let activity = try AccountActivity.decodeReply(Data(json.utf8))
        XCTAssertEqual(activity.dailyUsageBuckets, [.init(startDate: "2026-10-27", tokens: 20), .init(startDate: "2026-10-29", tokens: 22)])
        XCTAssertEqual(activity.latestDay, "2026-10-29")
        for invalid in ["2026-02-30", "2026-13-01", "2026-1-01", "PRIVATE"] {
            let data = try JSONSerialization.data(withJSONObject: ["summary": [:], "dailyUsageBuckets": [["startDate": invalid, "tokens": 1]]])
            XCTAssertThrowsError(try AccountActivity.decodeReply(data))
        }
        XCTAssertThrowsError(try AccountActivity.decodeReply(Data(#"{"summary":{"lifetimeTokens":-1}}"#.utf8)))
    }
    func testSharesNeverCombineUnknownLocalAmountsOrRemovedAccounts() {
        let now = Date()
        let states: [String: AccountActivityState] = [
            "a": .init(snapshot: .init(summary: .init(lifetimeTokens: 60), fetchedAt: now)),
            "b": .init(snapshot: .init(summary: .init(lifetimeTokens: 40), fetchedAt: now)),
            "removed": .init(snapshot: .init(summary: .init(lifetimeTokens: 10000), fetchedAt: now))
        ]
        let complete = AccountActivityTotals(accountIDs: ["a", "b", "a"], states: states, now: now)
        XCTAssertEqual(complete.total, 100)
        XCTAssertEqual(complete.fraction(for: "a"), 0.6)
        XCTAssertTrue(complete.complete)
        let partial = AccountActivityTotals(accountIDs: ["a", "missing"], states: states, now: now)
        XCTAssertEqual(partial.total, 60)
        XCTAssertFalse(partial.complete)
        XCTAssertNil(partial.fraction(for: "a"))
        XCTAssertNil(AccountActivityTotals(accountIDs: [], states: states).total)
        let zeros: [String: AccountActivityState] = ["a": .init(snapshot: .init(summary: .init(lifetimeTokens: 0)))]
        XCTAssertEqual(AccountActivityTotals(accountIDs: ["a"], states: zeros).total, 0)
        XCTAssertNil(AccountActivityTotals(accountIDs: ["a"], states: zeros).fraction(for: "a"))
    }
    func testCachedValuesSurviveFailedRefreshAndOverflowDoesNotProduceFalseTotal() {
        let now = Date()
        let state = AccountActivityState(snapshot: .init(summary: .init(lifetimeTokens: 80), fetchedAt: now), error: "offline")
        let result = AccountActivityTotals(accountIDs: ["a"], states: ["a": state], now: now)
        XCTAssertEqual(result.total, 80); XCTAssertTrue(result.cached)
        XCTAssertFalse(AccountActivityState(error: "offline").isCached(at: now))
        XCTAssertTrue(AccountActivityState(snapshot: state.snapshot).isCached(at: now.addingTimeInterval(901)))
        let overflow = AccountActivityTotals(accountIDs: ["a", "b"], states: [
            "a": .init(snapshot: .init(summary: .init(lifetimeTokens: Int.max))),
            "b": .init(snapshot: .init(summary: .init(lifetimeTokens: 1)))
        ])
        XCTAssertNil(overflow.total); XCTAssertFalse(overflow.complete)
    }
    private func auth(user: String, account: String) throws -> Data {
        let claims: [String: Any] = ["https://api.openai.com/auth": ["chatgpt_user_id": user]]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
        return try JSONSerialization.data(withJSONObject: ["tokens": ["id_token": "header.\(payload).signature", "account_id": account, "access_token": "PRIVATE-AUTH"]])
    }
    private func prepareAuth() throws -> (URL, URL, Data, Data) {
        let home = root.appendingPathComponent("source")
        let saved = home.appendingPathComponent("accounts")
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        let active = try auth(user: "other-user", account: "same-workspace")
        let wanted = try auth(user: "wanted-user", account: "same-workspace")
        try active.write(to: home.appendingPathComponent("auth.json"))
        let snapshot = saved.appendingPathComponent("wanted.auth.json"); try wanted.write(to: snapshot)
        return (home, snapshot, active, wanted)
    }
    private func script(_ body: String) throws -> URL {
        let file = root.appendingPathComponent("fake-codex")
        try ("#!/bin/sh\n" + body).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }
    func testRPCUsesMatchingStableIdentityInPrivateHomeAndCleansUp() async throws {
        let (home, snapshot, active, wanted) = try prepareAuth()
        let marker = root.appendingPathComponent("isolated-home.txt")
        let executable = try script("""
        [ "$CODEX_HOME" != '\(home.path)' ] || exit 8
        [ "$CODEX_SQLITE_HOME" = "$CODEX_HOME" ] || exit 9
        [ "$(stat -f %Lp "$CODEX_HOME/auth.json")" = 600 ] || exit 10
        [ "$(stat -f %Lp "$CODEX_HOME")" = 700 ] || exit 11
        cmp "$CODEX_HOME/auth.json" '\(snapshot.path)' || exit 12
        printf '%s' "$CODEX_HOME" > '\(marker.path)'
        while IFS= read -r line; do
          case "$line" in
            *account*usage*read*) printf '%s\\n' '{"method":"notice"}' '{"id":3,"result":{"summary":{"lifetimeTokens":123},"dailyUsageBuckets":[{"startDate":"2026-10-27","tokens":23}],"accessToken":"PRIVATE-REPLY"}}' ;;
            *account*read*) printf '%s\\n' '{"id":2,"result":{"account":{"type":"chatgpt"}}}' ;;
            *'"method":"initialize"'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
          esac
        done
        """)
        let backend = CodexAccountActivityBackend(executable: executable, codexHome: home, temporaryRoot: root, timeout: 2)
        let result = try await backend.read(accountID: "wanted-user::same-workspace")
        XCTAssertEqual(result.summary.lifetimeTokens, 123)
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("auth.json")), active)
        XCTAssertEqual(try Data(contentsOf: snapshot), wanted)
        let isolated = try String(contentsOf: marker, encoding: .utf8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains("PRIVATE"))
        XCTAssertThrowsError(try SavedAccountAuth.load(accountID: "missing::same-workspace", home: home))
    }
    func testTimeoutAndRPCErrorAreBoundedRedactedAndRemovePrivateDirectory() async throws {
        let (home, _, _, _) = try prepareAuth()
        var executable = try script("IFS= read -r line\nprintf '%s\\n' '{\"id\":1,\"error\":{\"code\":-32601,\"message\":\"PRIVATE-AUTH\"}}'\nexec /bin/sleep 5\n")
        var backend = CodexAccountActivityBackend(executable: executable, codexHome: home, temporaryRoot: root, timeout: 2)
        do { _ = try await backend.read(accountID: "wanted-user::same-workspace"); XCTFail("Expected error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("版本"), error.localizedDescription); XCTAssertFalse(error.localizedDescription.contains("PRIVATE")) }
        executable = try script("exec /bin/sleep 5\n")
        backend = CodexAccountActivityBackend(executable: executable, codexHome: home, temporaryRoot: root, timeout: 0.05)
        do { _ = try await backend.read(accountID: "wanted-user::same-workspace"); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(remaining.contains { $0.hasPrefix("codexeyes-activity-") })
    }
    func testMalformedRPCResultDoesNotExposeRawContentOrLeaveCredentials() async throws {
        let (home, _, active, _) = try prepareAuth()
        let executable = try script("IFS= read -r line\nprintf '%s\\n' '{\"id\":1,\"result\":\"PRIVATE-AUTH\"}'\nexec /bin/sleep 5\n")
        let backend = CodexAccountActivityBackend(executable: executable, codexHome: home, temporaryRoot: root, timeout: 2)
        do { _ = try await backend.read(accountID: "wanted-user::same-workspace"); XCTFail("Expected invalid result") }
        catch { XCTAssertFalse(error.localizedDescription.contains("PRIVATE")) }
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("auth.json")), active)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("codexeyes-activity-") })
    }

    func testReadOnlySnapshotCannotRotateSourceRefreshToken() throws {
        let source = try auth(user: "wanted", account: "workspace")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
        var tokens = try XCTUnwrap(object["tokens"] as? [String: Any])
        tokens["refresh_token"] = "PRIVATE-REFRESH-CREDENTIAL"
        object["tokens"] = tokens
        let original = try JSONSerialization.data(withJSONObject: object)
        let copy = try SavedAccountAuth.readOnlyCopy(original)
        let copiedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: copy) as? [String: Any])
        let copiedTokens = try XCTUnwrap(copiedObject["tokens"] as? [String: Any])
        XCTAssertEqual(copiedTokens["refresh_token"] as? String, "")
        XCTAssertEqual(copiedTokens["access_token"] as? String, "PRIVATE-AUTH")
        XCTAssertEqual(SavedAccountAuth.key(in: copy), "wanted::workspace")
        XCTAssertFalse(String(decoding: copy, as: UTF8.self).contains("PRIVATE-REFRESH-CREDENTIAL"))
        XCTAssertTrue(String(decoding: original, as: UTF8.self).contains("PRIVATE-REFRESH-CREDENTIAL"))
    }

    func testExitedChildCannotCrashHostAndPrivateHomeIsRemoved() async throws {
        let (home, _, _, _) = try prepareAuth()
        let executable = try script("exit 2\n")
        let backend = CodexAccountActivityBackend(executable: executable, codexHome: home, temporaryRoot: root, timeout: 2)
        do { _ = try await backend.read(accountID: "wanted-user::same-workspace"); XCTFail("Expected child failure") }
        catch { XCTAssertFalse(error.localizedDescription.contains("PRIVATE")) }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("codexeyes-activity-") })
    }

}
