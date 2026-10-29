import XCTest
@testable import CodexEyesCore

final class CoreTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexEyesTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }
    private func account(now: Date, remaining: Double = 50) -> Account {
        Account(id: "a", usage: .init(source: "api", primary: .init(usedPercent: 100 - remaining, windowMinutes: 300, resetsAt: now.timeIntervalSince1970 + 100),
                                      secondary: .init(usedPercent: 20, windowMinutes: 10080, resetsAt: now.timeIntervalSince1970 + 200),
                                      refresh: .init(status: "ok")), lastConfirmedAt: now)
    }
    func testAvailabilityRequiresFreshSuccessfulConfirmation() {
        let now = Date(); var a = account(now: now)
        XCTAssertEqual(a.availability(at: now), .available)
        XCTAssertEqual(a.availability(at: now.addingTimeInterval(601)), .unknown("待确认 · 数据未更新"))
        a.usage?.refresh = .init(status: "http_error", httpStatus: 503)
        XCTAssertEqual(a.availability(at: now), .unknown("访问错误 503"))
        a.usage?.refresh = .init(status: "http_error", httpStatus: 401)
        XCTAssertEqual(a.availability(at: now), .loginRequired)
        a.usage?.refresh = .init(status: "http_error", httpStatus: 403)
        XCTAssertEqual(a.availability(at: now), .unknown("访问错误 403"))
    }
    func testSingleWindowPlanAndExpiredReset() {
        let now = Date(); var a = account(now: now)
        a.usage?.secondary = nil
        XCTAssertEqual(a.availability(at: now), .available)
        a.usage?.primary?.resetsAt = now.timeIntervalSince1970 - 1
        XCTAssertEqual(a.availability(at: now), .unknown("重置已到 · 等待刷新"))
        a = account(now: now, remaining: 0)
        XCTAssertEqual(a.availability(at: now), .limited)
    }
    func testViewSwitchDoesNotChangeConfiguredOrVerifiedIdentity() {
        var state = IdentityState()
        let list = DemoData.accounts(); state.reconcile(list)
        for _ in 0..<100 { state.view("demo-spare"); state.view("demo-main") }
        state.view("demo-spare")
        XCTAssertEqual(state.configuredAccountID, "demo-main")
        XCTAssertNil(state.verifiedRuntimeAccountID)
        state.panelOpened(); XCTAssertEqual(state.viewedAccountID, "demo-main")
    }
    func testDecodeUnknownFieldsAndAbsentSecondary() throws {
        let json = #"{"schema_version":1,"active_account_key":"stable","accounts":[{"account_key":"stable","future":42,"usage":{"source":"cache","primary":{"used_percent":31,"window_minutes":60}}}]}"#
        let list = try JSONDecoder().decode(AccountList.self, from: Data(json.utf8))
        XCTAssertEqual(list.accounts[0].id, "stable")
        XCTAssertNil(list.accounts[0].usage?.secondary)
        XCTAssertEqual(list.accounts[0].usage?.primary?.label, "1h")
    }
    func testRuntimeGuardDetectsSharedClientAndDaemon() {
        let listing = "  1 /sbin/launchd\n22 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT\n33 /usr/local/bin/codex\n44 /tmp/CodexEyes\n55 /tmp/codex-auth\n"
        XCTAssertEqual(RuntimeGuard.blockingProcesses(in: listing).sorted(), ["chatgpt", "codex"])
        XCTAssertTrue(RuntimeGuard.blockingProcesses(in: "1 /tmp/CodexEyes\n2 /tmp/codex-auth").isEmpty)
    }
    private func line(_ type: String, _ payload: [String: Any], second: Int) throws -> Data {
        let object: [String: Any] = ["type": type, "timestamp": String(format: "2026-10-28T10:00:%02dZ", second), "payload": payload]
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]); data.append(10); return data
    }
    private func meta(_ id: String, second: Int = 0, child: Bool = false) throws -> Data {
        var payload: [String: Any] = ["id": id, "cwd": "/private/SECRET-PATH/project", "timestamp": String(format: "2026-10-28T10:00:%02dZ", second)]
        if child { payload["forked_from_id"] = "parent" }
        return try line("session_meta", payload, second: second)
    }
    func testHookOnlySessionsRemainForAlertsButNotUsageSelection() throws {
        let index = LogIndex()
        index.apply(try XCTUnwrap(HookEvent(input: ["session_id": "session-a", "hook_event_name": "PermissionRequest", "cwd": "/work/coding"])))
        XCTAssertEqual(index.snapshot().sessions.count, 1)
        XCTAssertEqual(index.snapshot().sessions.first?.status, .permission)
        XCTAssertTrue(index.snapshot().usageSessions.isEmpty)
        let file = directory.appendingPathComponent("later-log.jsonl")
        var data = try meta("session-a")
        data.append(try token(100, last: 100, second: 1))
        try data.write(to: file); try index.ingest(file: file)
        let result = index.snapshot()
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.usageSessions.first?.totalOwned.total, 100)
        XCTAssertEqual(result.daily(LogIndex.date("2026-10-28T10:00:01Z")!), 100)
    }
    func testRecordedZeroUsageIsStillSelectableAndUntitledSessionsAreDistinct() {
        var one = SessionSummary(id: "first-id-123"), two = SessionSummary(id: "second-id-123")
        one.project = "coding"; two.project = "coding"
        one.contextRecordedAt = Date(); two.totalOwned = TokenUsage(total: 10)
        let snapshot = LocalSnapshot(sessions: [one, two], deltas: [], warnings: [])
        XCTAssertEqual(snapshot.usageSessions.count, 2)
        XCTAssertNotEqual(one.displayTitle, two.displayTitle)
        XCTAssertFalse(one.displayTitle == "coding")
    }
    func testLongMenuTitlesAreBoundedWithoutChangingFullTitle() {
        var session = SessionSummary(id: "long-title")
        let title = String(repeating: "会话标题", count: 30)
        session.title = title
        XCTAssertEqual(session.menuTitle.count, 37)
        XCTAssertEqual(session.displayTitle, title)
        session.title = "Line one\nLine two"
        XCTAssertFalse(session.menuTitle.contains("\n"))
    }
    private func token(_ total: Int, last: Int, second: Int) throws -> Data {
        try line("event_msg", ["type": "token_count", "info": [
            "total_token_usage": ["input_tokens": total - 10, "output_tokens": 10, "total_tokens": total],
            "last_token_usage": ["input_tokens": max(0, last - 10), "output_tokens": 10, "total_tokens": last],
            "model_context_window": 200000]], second: second)
    }
    func testIncrementalPartialLinesDuplicatesAndArchivedCopies() throws {
        let file = directory.appendingPathComponent("test.jsonl")
        var data = try meta("one"); data.append(try token(100, last: 100, second: 1)); try data.write(to: file)
        let index = LogIndex(); try index.ingest(file: file)
        XCTAssertEqual(index.snapshot().deltas.reduce(0) { $0 + $1.usage.total }, 100)
        let next = try token(150, last: 50, second: 2)
        let split = next.count / 2
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: next.prefix(split)); try handle.close()
        try index.ingest(file: file)
        XCTAssertEqual(index.snapshot().deltas.count, 1)
        let append = try FileHandle(forWritingTo: file); try append.seekToEnd(); try append.write(contentsOf: next.dropFirst(split)); try append.close()
        try index.ingest(file: file); try index.ingest(file: file)
        let copy = directory.appendingPathComponent("archive.jsonl"); try FileManager.default.copyItem(at: file, to: copy)
        try index.ingest(file: copy)
        XCTAssertEqual(index.snapshot().deltas.reduce(0) { $0 + $1.usage.total }, 150)
        XCTAssertEqual(index.snapshot().sessions[0].lastUsage.total, 50)
        XCTAssertEqual(index.snapshot().sessions[0].contextRatio, 0.0002)
    }
    func testChildReplayEstablishesBaselineWithoutCountingParent() throws {
        let child = directory.appendingPathComponent("child.jsonl")
        var data = try meta("child", second: 10, child: true)
        data.append(try token(100, last: 100, second: 1))
        data.append(try token(150, last: 50, second: 11)); try data.write(to: child)
        let index = LogIndex(); try index.ingest(file: child)
        XCTAssertEqual(index.snapshot().sessions[0].totalOwned.total, 50)
    }
    func testChildWithoutReplayedBaselineUsesLatestRequestOnly() throws {
        let child = directory.appendingPathComponent("child.jsonl")
        var data = try meta("child", second: 10, child: true)
        data.append(try token(10150, last: 50, second: 11)); try data.write(to: child)
        let index = LogIndex(); try index.ingest(file: child)
        XCTAssertEqual(index.snapshot().sessions[0].totalOwned.total, 50)
    }
    func testIndependentSessionsWithSameCountersCountSeparately() throws {
        let index = LogIndex()
        for id in ["a", "b"] {
            let file = directory.appendingPathComponent(id + ".jsonl")
            var data = try meta(id); data.append(try token(100, last: 100, second: 1)); try data.write(to: file)
            try index.ingest(file: file)
        }
        XCTAssertEqual(index.snapshot().deltas.reduce(0) { $0 + $1.usage.total }, 200)
    }
    func testCompactionAndInterruptedTurnRemainDistinct() throws {
        let file = directory.appendingPathComponent("test.jsonl")
        var data = try meta("a"); data.append(try token(100, last: 100, second: 1))
        data.append(try line("compacted", [:], second: 2))
        data.append(try line("event_msg", ["type": "turn_aborted"], second: 3))
        try data.write(to: file)
        let index = LogIndex(); try index.ingest(file: file)
        let session = index.snapshot().sessions[0]
        XCTAssertEqual(session.compactions, 1); XCTAssertEqual(session.status, .interrupted)
        XCTAssertEqual(session.totalOwned.total, 100)
    }
    func testIndexPersistsMetadataWithoutConversationContent() throws {
        let file = directory.appendingPathComponent("test.jsonl")
        var data = try meta("a")
        data.append(try line("response_item", ["content": "TOP-SECRET-CONVERSATION"], second: 1))
        data.append(try token(100, last: 100, second: 2)); try data.write(to: file)
        let index = LogIndex(); try index.ingest(file: file)
        let cache = directory.appendingPathComponent("index.json"); try index.save(to: cache)
        XCTAssertFalse(try String(contentsOf: cache).contains("TOP-SECRET-CONVERSATION"))
        let loaded = LogIndex.load(from: cache); try loaded.ingest(file: file)
        XCTAssertEqual(loaded.snapshot().deltas.count, 1)
    }
    func testHooksMergeIdempotentlyAndDisconnectPreservesOthers() throws {
        let file = directory.appendingPathComponent("hooks.json")
        let original: [String: Any] = ["custom": "keep", "hooks": ["Stop": [["matcher": "keep", "hooks": [["type": "command", "command": "echo OTHER"]]]]]]
        try JSONSerialization.data(withJSONObject: original).write(to: file)
        let helper = URL(fileURLWithPath: "/Applications/Creator's Tools/CodexEyesHook")
        try HookConfiguration.update(home: directory, helper: helper, enabled: true)
        try HookConfiguration.update(home: directory, helper: helper, enabled: true)
        XCTAssertTrue(HookConfiguration.installed(home: directory))
        let installed = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let stop = (installed["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2)
        try HookConfiguration.update(home: directory, helper: helper, enabled: false)
        XCTAssertFalse(HookConfiguration.installed(home: directory))
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! NSDictionary
        XCTAssertEqual(restored, original as NSDictionary)
    }
    func testInvalidHooksNotOverwritten() throws {
        let file = directory.appendingPathComponent("hooks.json"); let bad = Data("{ invalid".utf8); try bad.write(to: file)
        XCTAssertThrowsError(try HookConfiguration.update(home: directory, helper: directory, enabled: true))
        XCTAssertEqual(try Data(contentsOf: file), bad)
    }
    func testHookReceiverOnlyStoresAllowlistedMetadata() throws {
        let input: [String: Any] = ["session_id": "one", "hook_event_name": "PermissionRequest", "cwd": "/secret/project",
                                    "prompt": "SECRET", "tool_input": ["command": "SECRET"]]
        let event = try XCTUnwrap(HookEvent(input: input)); try HookRecorder.record(event, directory: directory)
        let text = try String(contentsOf: directory.appendingPathComponent("events.jsonl"))
        XCTAssertFalse(text.contains("SECRET")); XCTAssertFalse(text.contains("/secret/"))
        let index = LogIndex(); index.apply(event)
        XCTAssertEqual(index.snapshot().sessions[0].status, .permission)
        let stop = try XCTUnwrap(HookEvent(input: ["session_id": "one", "hook_event_name": "Stop"], date: event.date.addingTimeInterval(1)))
        index.apply(stop); XCTAssertEqual(index.snapshot().sessions[0].status, .responseReady)
    }
    func testCommandRunnerDrainsLargeOutputAndTimesOut() async throws {
        let runner = CommandRunner()
        let large = try await runner.run(URL(fileURLWithPath: "/usr/bin/head"), arguments: ["-c", "200000", "/dev/zero"])
        XCTAssertEqual(large.data.count, 200000)
        do {
            _ = try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
    }
    func testBackendPassesStableSelectorWithoutShellInterpolation() async throws {
        let executable = directory.appendingPathComponent("fake-backend")
        let script = "#!/bin/sh\nif [ \"$1\" = switch ]; then\n [ \"$2\" = 'stable::account' ] || exit 1\n printf '{\"schema_version\":1,\"command\":\"switch\",\"switched_to\":{}}'\nelse\n printf '{\"schema_version\":1,\"accounts\":[],\"active_account_key\":null}'\nfi\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let backend = CLIAccountBackend(executable: executable, codexHome: directory)
        try await backend.activate(id: "stable::account")
        let list = try await backend.list(remote: false); XCTAssertTrue(list.accounts.isEmpty)
    }
    func testNewerLogFailureOverridesHistoricalHookState() throws {
        let index = LogIndex()
        let early = try XCTUnwrap(LogIndex.date("2026-10-28T10:00:00Z"))
        index.apply(try XCTUnwrap(HookEvent(input: ["session_id": "a", "hook_event_name": "UserPromptSubmit"], date: early)))
        let file = directory.appendingPathComponent("failure.jsonl")
        var data = try meta("a"); data.append(try line("event_msg", ["type": "error"], second: 4)); try data.write(to: file)
        try index.ingest(file: file)
        XCTAssertEqual(index.snapshot().sessions[0].status, .failed)
        index.apply(try XCTUnwrap(HookEvent(input: ["session_id": "a", "hook_event_name": "Stop"], date: early)))
        XCTAssertEqual(index.snapshot().sessions[0].status, .failed)
    }
    func testCounterResetCountsOnlyNewUsage() throws {
        let file = directory.appendingPathComponent("reset.jsonl")
        var data = try meta("a"); data.append(try token(100, last: 100, second: 1))
        data.append(try token(30, last: 30, second: 2)); data.append(try token(50, last: 20, second: 3))
        try data.write(to: file)
        let index = LogIndex(); try index.ingest(file: file)
        XCTAssertEqual(index.snapshot().sessions[0].totalOwned.total, 150)
    }
    func testOversizedContentDoesNotWedgeFollowingMetadata() throws {
        let file = directory.appendingPathComponent("large.jsonl")
        var data = try meta("a")
        data.append(Data(repeating: 120, count: 9 * 1024 * 1024)); data.append(10)
        data.append(try token(50, last: 50, second: 2)); try data.write(to: file)
        let index = LogIndex(); try index.ingest(file: file); try index.ingest(file: file)
        XCTAssertEqual(index.snapshot().sessions[0].totalOwned.total, 50)
    }
    func testTruncatedFileReindexesWithoutDoubleCountingRetainedEvents() throws {
        let file = directory.appendingPathComponent("truncated.jsonl")
        var full = try meta("a"); full.append(try token(50, last: 50, second: 1)); full.append(try token(100, last: 50, second: 2))
        try full.write(to: file)
        let index = LogIndex(); try index.ingest(file: file)
        var truncated = try meta("a"); truncated.append(try token(50, last: 50, second: 1)); try truncated.write(to: file)
        try index.ingest(file: file)
        XCTAssertEqual(index.snapshot().sessions[0].totalOwned.total, 100)
    }
    func testBackendRejectsUnknownSchemaAndStructuredErrors() async throws {
        let executable = directory.appendingPathComponent("fake-backend")
        try "#!/bin/sh\nprintf '{\"schema_version\":2,\"accounts\":[]}'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let backend = CLIAccountBackend(executable: executable, codexHome: directory)
        do { _ = try await backend.list(remote: false); XCTFail("Expected schema rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("版本")) }
        try "#!/bin/sh\nprintf '{\"error\":{\"code\":\"state_uncertain\",\"message\":\"PRIVATE\"}}'\nexit 1\n".write(to: executable, atomically: true, encoding: .utf8)
        do { try await backend.activate(id: "a"); XCTFail("Expected structured error") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("state_uncertain"))
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE"))
        }
    }
    func testCommandRunnerSerializesConcurrentOperations() async throws {
        let executable = directory.appendingPathComponent("serialized")
        let marker = directory.appendingPathComponent("lock").path
        let script = "#!/bin/sh\nmkdir '\(marker)' || exit 7\nsleep 0.1\nrmdir '\(marker)'\nprintf '{}'\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let runner = CommandRunner()
        async let one = runner.run(executable, arguments: [])
        async let two = runner.run(executable, arguments: [])
        let outputs = try await [one, two]
        XCTAssertTrue(outputs.allSatisfy { $0.exitCode == 0 })
    }
    func testSystemProxyTranslationRespectsExplicitEnvironmentAndLoopback() {
        let settings: [String: Any] = ["HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897,
                                      "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 7897,
                                      "ExceptionsList": ["*.local", "<local>"]]
        let mapped = NetworkEnvironment.proxy(settings: settings, inherited: [:])
        XCTAssertEqual(mapped["https_proxy"], "http://127.0.0.1:7897")
        XCTAssertEqual(mapped["all_proxy"], "socks5h://127.0.0.1:7897")
        XCTAssertTrue(mapped["no_proxy"]?.contains("localhost") == true)
        XCTAssertEqual(NetworkEnvironment.proxy(settings: settings, inherited: ["HTTPS_PROXY": "http://custom:123"]), [:])
        XCTAssertNil(NetworkEnvironment.proxy(settings: ["HTTPSEnable": 1, "HTTPSProxy": "x", "HTTPSPort": -1], inherited: [:])["https_proxy"])
    }
    func testProfileNameUsesLocalIdentityAndStableAccountKey() throws {
        let claims: [String: Any] = ["name": "Taylor Lin", "https://api.openai.com/auth": ["chatgpt_user_id": "user-one", "chatgpt_account_id": "personal"]]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let credentials: [String: Any] = ["tokens": ["id_token": "header.\(payload).signature", "account_id": "workspace", "access_token": "DO-NOT-STORE"]]
        let file = directory.appendingPathComponent("auth.json")
        try JSONSerialization.data(withJSONObject: credentials).write(to: file)
        let names = LocalProfileNames.load(home: directory)
        XCTAssertEqual(names["user-one::workspace"], "Taylor Lin")
        var account = Account(id: "user-one::workspace", email: "fallback@example.com", alias: "old alias")
        account.profileName = names[account.id]
        XCTAssertEqual(account.displayName, "Taylor Lin")
        let cache = try JSONEncoder().encode(account)
        XCTAssertFalse(String(decoding: cache, as: UTF8.self).contains("DO-NOT-STORE"))
        XCTAssertNil(LocalProfileNames.parse(Data("{}".utf8)))
    }
    func testShortResetFormattingAndWeeklyLabel() {
        let now = Date()
        XCTAssertEqual(CompactTime.remaining(until: now.addingTimeInterval(8100), now: now), "2h15m")
        XCTAssertEqual(CompactTime.remaining(until: now.addingTimeInterval(7200), now: now), "2h")
        XCTAssertEqual(CompactTime.remaining(until: now.addingTimeInterval(187200), now: now), "2d4h")
        XCTAssertEqual(CompactTime.remaining(until: now.addingTimeInterval(20), now: now), "1m")
        XCTAssertEqual(QuotaWindow(usedPercent: 20, windowMinutes: 10080).label, "Weekly")
    }
    func testAccountCardShowsRecoveryOnlyAfterAllBlockedWindowsReset() {
        let now = Date()
        var blocked = account(now: now, remaining: 0)
        blocked.usage?.primary?.resetsAt = now.addingTimeInterval(3600).timeIntervalSince1970
        blocked.usage?.secondary = .init(usedPercent: 100, windowMinutes: 10080, resetsAt: now.addingTimeInterval(14400).timeIntervalSince1970)
        XCTAssertEqual(blocked.availabilitySummary(at: now), "4小时后可用")
        blocked.usage?.secondary?.resetsAt = nil
        XCTAssertEqual(blocked.availabilitySummary(at: now), "额度已用尽")
    }
    func testRealThreadTitlesReplaceDuplicateFolderNames() throws {
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try meta("one").write(to: sessions.appendingPathComponent("one.jsonl"))
        let titles = Data("{\"id\":\"one\",\"thread_name\":\"监控助手开发\",\"updated_at\":\"2026-10-29\"}\n".utf8)
        try titles.write(to: directory.appendingPathComponent("session_index.jsonl"))
        let snapshot = LogIndex().scan(home: directory)
        XCTAssertEqual(snapshot.sessions.first?.displayTitle, "监控助手开发")
        XCTAssertEqual(snapshot.sessions.first?.project, "project")
    }
    func testChineseQuotaTimeAndCacheRatio() {
        let now = Date()
        XCTAssertEqual(CompactTime.localizedRemaining(until: now.addingTimeInterval(8100), now: now), "2小时15分")
        XCTAssertEqual(CompactTime.localizedRemaining(until: now.addingTimeInterval(187200), now: now), "2天4小时")
        XCTAssertEqual(QuotaWindow(usedPercent: 10, windowMinutes: 300).localizedLabel, "5小时")
        XCTAssertEqual(QuotaWindow(usedPercent: 10, windowMinutes: 10080).localizedLabel, "每周")
        XCTAssertNil(TokenUsage().cacheHitRate)
        XCTAssertEqual(TokenUsage(input: 100, cached: 80).cacheHitRate, 0.8)
        XCTAssertEqual(TokenUsage(input: 100, cached: 200).cacheHitRate, 1)
    }
    func testDashboardDailyTotalsRespectMidnightAndTimezone() throws {
        let midnight = try XCTUnwrap(LogIndex.date("2026-10-29T00:00:00Z"))
        let deltas = [
            UsageDelta(id: "before", sessionID: "a", date: midnight.addingTimeInterval(-1), usage: .init(total: 100)),
            UsageDelta(id: "at", sessionID: "a", date: midnight, usage: .init(total: 200)),
            UsageDelta(id: "next", sessionID: "a", date: midnight.addingTimeInterval(86400), usage: .init(total: 400))
        ]
        let snapshot = LocalSnapshot(sessions: [], deltas: deltas, warnings: [])
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var shanghai = utc; shanghai.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        XCTAssertEqual(snapshot.daily(midnight, calendar: utc), 200)
        XCTAssertEqual(snapshot.daily(midnight, calendar: shanghai), 300)
    }
    func testUsageBreakdownKeepsUnknownInDenominatorAndReconcilesTotals() throws {
        let now = Date()
        let deltas = [
            UsageDelta(id: "a", sessionID: "one", date: now, usage: .init(total: 60), accountKey: "a"),
            UsageDelta(id: "b", sessionID: "two", date: now, usage: .init(total: 20), accountKey: "b"),
            UsageDelta(id: "unknown", sessionID: "one", date: now, usage: .init(total: 10)),
            UsageDelta(id: "removed", sessionID: "three", date: now, usage: .init(total: 10), accountKey: "removed")
        ]
        let report = UsageBreakdown(deltas: deltas, accountKeys: ["a", "b"])
        XCTAssertEqual(report.total, 100)
        XCTAssertEqual(report.byAccount, ["a": 60, "b": 20])
        XCTAssertEqual(report.unassigned, 20)
        XCTAssertEqual(report.byAccount.values.reduce(0, +) + report.unassigned, report.total)
        XCTAssertEqual(report.fraction(60), 0.6)
        XCTAssertEqual(report.fraction(report.unassigned), 0.2)
        XCTAssertNil(UsageBreakdown(deltas: [], accountKeys: []).fraction(0))
    }
    func testUsageBreakdownDateRangeUsesSameScopeForSharesAndTotals() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let deltas = [
            UsageDelta(id: "old", sessionID: "a", date: start.addingTimeInterval(-1), usage: .init(total: 500), accountKey: "a"),
            UsageDelta(id: "today", sessionID: "b", date: start, usage: .init(total: 100), accountKey: "b"),
            UsageDelta(id: "tomorrow", sessionID: "b", date: start.addingTimeInterval(86400), usage: .init(total: 200), accountKey: "b")
        ]
        let today = UsageBreakdown(deltas: deltas, accountKeys: ["a", "b"], interval: DateInterval(start: start, duration: 86400))
        XCTAssertEqual(today.total, 100)
        XCTAssertEqual(today.byAccount, ["b": 100])
        let all = UsageBreakdown(deltas: deltas, accountKeys: ["a", "b"])
        XCTAssertEqual(all.total, 800)
        XCTAssertEqual(all.firstRecordedAt, start.addingTimeInterval(-1))
    }
    func testSessionCreatorDoesNotProveUsageAccountAndOldCacheRemainsReadable() throws {
        let file = directory.appendingPathComponent("creator.jsonl")
        var data = try line("session_meta", ["id": "one", "creator_user_id": "user", "creator_account_id": "account"], second: 0)
        data.append(try token(100, last: 100, second: 1))
        try data.write(to: file)
        let index = LogIndex(); try index.ingest(file: file)
        XCTAssertNil(index.snapshot().deltas.first?.accountKey)
        let report = UsageBreakdown(deltas: index.snapshot().deltas, accountKeys: ["user::account"])
        XCTAssertEqual(report.unassigned, 100)
        XCTAssertTrue(report.byAccount.isEmpty)
        let encoded = try JSONEncoder().encode(index.snapshot().deltas[0])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "accountKey")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(UsageDelta.self, from: oldData).accountKey)
    }

    func testMenuBarPrefersFiveHoursAndFallsBackToWeeklyRegardlessOfPlan() {
        let now = Date()
        var current = account(now: now, remaining: 12)
        current.plan = "pro"
        XCTAssertEqual(MenuBarQuota.title(for: current, now: now), "12%")
        XCTAssertEqual(MenuBarQuota.window(for: current)?.windowMinutes, 300)
        current.usage?.primary = nil
        XCTAssertEqual(MenuBarQuota.title(for: current, now: now), "80%")
        XCTAssertEqual(MenuBarQuota.summary(for: current, now: now), "每周剩余 80%")
        current.usage?.primary = .init(usedPercent: 100, windowMinutes: 300, resetsAt: now.timeIntervalSince1970 + 100)
        XCTAssertEqual(MenuBarQuota.title(for: current, now: now), "0%")
        let primary = current.usage?.primary
        let secondary = current.usage?.secondary
        current.usage?.primary = secondary
        current.usage?.secondary = primary
        XCTAssertEqual(MenuBarQuota.title(for: current, now: now), "0%")
    }
    func testMenuBarDoesNotShowStaleOrFailedQuotaAsCurrent() {
        let now = Date(); var current = account(now: now)
        XCTAssertEqual(MenuBarQuota.title(for: current, now: now.addingTimeInterval(601)), "—")
        current.usage?.refresh = .init(status: "http_error", httpStatus: 401)
        XCTAssertEqual(MenuBarQuota.title(for: current, now: now), "—")
        XCTAssertEqual(MenuBarQuota.title(for: nil, now: now), "—")
    }

}
