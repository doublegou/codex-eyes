import Foundation
import CryptoKit

public enum SessionStatus: String, Codable, Sendable {
    case recorded, running, permission, responseReady, interrupted, failed, compacting, ended
    public var label: String {
        switch self {
        case .recorded: return L("最近有记录")
        case .running: return L("运行中")
        case .permission: return L("等待授权")
        case .responseReady: return L("本轮已结束")
        case .interrupted: return L("已中断")
        case .failed: return L("运行失败")
        case .compacting: return L("正在压缩上下文")
        case .ended: return L("会话已结束")
        }
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var input: Int = 0
    public var cached: Int = 0
    public var output: Int = 0
    public var reasoning: Int = 0
    public var total: Int = 0
    public var cacheHitRate: Double? {
        guard input > 0 else { return nil }
        return min(1, max(0, Double(cached) / Double(input)))
    }
    public init(input: Int = 0, cached: Int = 0, output: Int = 0, reasoning: Int = 0, total: Int = 0) {
        self.input = input; self.cached = cached; self.output = output; self.reasoning = reasoning; self.total = total
    }
    init(_ dict: [String: Any]) {
        input = dict["input_tokens"] as? Int ?? 0
        cached = dict["cached_input_tokens"] as? Int ?? 0
        output = dict["output_tokens"] as? Int ?? 0
        reasoning = dict["reasoning_output_tokens"] as? Int ?? 0
        total = dict["total_tokens"] as? Int ?? input + output
    }
    func delta(from old: TokenUsage) -> TokenUsage {
        .init(input: max(0, input - old.input), cached: max(0, cached - old.cached),
              output: max(0, output - old.output), reasoning: max(0, reasoning - old.reasoning), total: max(0, total - old.total))
    }
    static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        .init(input: a.input + b.input, cached: a.cached + b.cached, output: a.output + b.output,
              reasoning: a.reasoning + b.reasoning, total: a.total + b.total)
    }
}

public struct SessionSummary: Codable, Identifiable, Sendable {
    public var id: String
    public var project: String = L("本机会话")
    public var title: String?
    public var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return L("未命名会话") + " · " + String(id.prefix(8))
    }
    /// Hook activity alone does not establish a token/context record.
    public var hasUsageRecord: Bool { contextRecordedAt != nil || totalOwned.total > 0 }
    public var menuTitle: String {
        let value = displayTitle.replacingOccurrences(of: "\n", with: " ")
        return value.count > 36 ? String(value.prefix(36)) + "…" : value
    }
    public var model: String?
    public var lastActivity: Date = .distantPast
    public var status: SessionStatus = .recorded
    public var lastUsage = TokenUsage()
    public var cumulative = TokenUsage()
    public var contextWindow: Int?
    public var contextRecordedAt: Date?
    public var compactions = 0
    public var totalOwned = TokenUsage()
    public var statusFromHook = false
    public var statusRecordedAt: Date?
    public var contextRatio: Double? {
        guard let limit = contextWindow, limit > 0, contextRecordedAt != nil else { return nil }
        return min(1, Double(lastUsage.input) / Double(limit))
    }
    public init(id: String) { self.id = id }
}

public struct UsageDelta: Codable, Sendable {
    public var id: String
    public var sessionID: String
    public var date: Date
    public var usage: TokenUsage
    /// Only a verified identity for this usage event may populate this field.
    /// Session creators and the currently configured login are not sufficient evidence.
    public var accountKey: String? = nil
}

private struct FileCursor: Codable {
    var offset: UInt64 = 0
    var sessionID: String = ""
    var createdAt: Date?
    var child = false
    var previous = TokenUsage()
    var seenSnapshot = false
    var fileNumber: UInt64 = 0
    var skippingLongLine = false
}

public struct LocalSnapshot: Sendable {
    public var sessions: [SessionSummary]
    public var deltas: [UsageDelta]
    public var warnings: [String]
    public init(sessions: [SessionSummary], deltas: [UsageDelta], warnings: [String]) {
        self.sessions = sessions; self.deltas = deltas; self.warnings = warnings
    }
    public var usageSessions: [SessionSummary] { sessions.filter(\.hasUsageRecord) }
    public func daily(_ date: Date, calendar: Calendar = .current) -> Int {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return 0 }
        return deltas.reduce(0) { total, delta in
            delta.date >= day.start && delta.date < day.end ? total + delta.usage.total : total
        }
    }
    public static func demo(now: Date = Date()) -> LocalSnapshot {
        var main = SessionSummary(id: "demo-session")
        main.project = "codex-eyes"; main.title = L("制作监控看板"); main.model = "Codex"; main.status = .running; main.statusFromHook = true
        main.lastActivity = now; main.contextRecordedAt = now; main.contextWindow = 200000
        main.lastUsage = .init(input: 84000, cached: 64000, output: 2400, reasoning: 1200, total: 86400)
        main.totalOwned = .init(input: 1100000, cached: 780000, output: 180000, total: 1280000)
        main.cumulative = main.totalOwned
        var second = SessionSummary(id: "demo-waiting")
        second.project = "personal-site"; second.title = L("搭建个人网站"); second.status = .permission; second.lastActivity = now; second.statusFromHook = true
        let deltas = (0..<7).flatMap { n in
            let total = [1280000, 820000, 1640000, 960000, 440000, 1080000, 720000][n]
            let date = Calendar.current.date(byAdding: .day, value: -n, to: now)!
            return [
            UsageDelta(id: "demo-\(n)", sessionID: main.id, date: Calendar.current.date(byAdding: .day, value: -n, to: now)!,
                       usage: .init(input: total * 3 / 5 - total / 50, output: total / 50, total: total * 3 / 5), accountKey: "demo-main"),
            UsageDelta(id: "demo-spare-\(n)", sessionID: second.id, date: date,
                       usage: .init(input: total - total * 3 / 5 - total / 100, output: total / 100,
                                    total: total - total * 3 / 5), accountKey: "demo-spare")
            ]
        }
        return .init(sessions: [main, second], deltas: deltas, warnings: [])
    }
}

/// Persistent metadata-only index. Never stores prompts, replies or tool arguments.
public final class LogIndex: Codable {
    private var cursors: [String: FileCursor] = [:]
    private var summaries: [String: SessionSummary] = [:]
    private var ledger: [String: UsageDelta] = [:]
    private var compactionIDs: Set<String> = []
    public init() {}
    public static func load(from url: URL) -> LogIndex {
        guard let data = try? Data(contentsOf: url), let index = try? JSONDecoder().decode(LogIndex.self, from: data) else { return LogIndex() }
        return index
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func scan(home: URL) -> LocalSnapshot {
        var warnings: Set<String> = []
        for root in [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")] {
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                                options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in iterator {
                if file.pathExtension == "zst" { warnings.insert(L("压缩日志暂未计入统计")); continue }
                guard file.pathExtension == "jsonl" else { continue }
                do { try ingest(file: file) } catch { warnings.insert(L("部分日志暂时无法读取")) }
            }
        }
        readTitles(home: home)
        return snapshot(warnings: Array(warnings))
    }
    private func readTitles(home: URL) {
        let file = home.appendingPathComponent("session_index.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 8_388_608 ? size - 8_388_608 : 0)
        guard let data = try? handle.readToEnd() else { return }
        for line in data.split(separator: 10) {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = entry["id"] as? String, let name = entry["thread_name"] as? String,
                  !name.isEmpty, var session = summaries[id] else { continue }
            session.title = String(name.prefix(200)); summaries[id] = session
        }
    }
    public func ingest(file: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let number = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        var cursor = cursors[file.path] ?? FileCursor()
        if cursor.offset > size || (cursor.fileNumber != 0 && cursor.fileNumber != number) { cursor = FileCursor() }
        cursor.fileNumber = number
        guard size > cursor.offset else { return }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        try handle.seek(toOffset: cursor.offset)
        // Chunking bounds memory for very large transcripts and handles partial trailing lines.
        var pending = Data(), consumed: UInt64 = 0
        while true {
            var chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { break }
            if cursor.skippingLongLine {
                if let newline = chunk.firstIndex(of: 10) {
                    let length = chunk.distance(from: chunk.startIndex, to: newline) + 1
                    consumed += UInt64(length); chunk.removeFirst(length); cursor.skippingLongLine = false
                } else { consumed += UInt64(chunk.count); continue }
            }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                if line.count <= 8 * 1024 * 1024 {
                    autoreleasepool { parse(Data(line), cursor: &cursor) }
                }
                let length = pending.distance(from: pending.startIndex, to: newline) + 1
                pending.removeFirst(length); consumed += UInt64(length)
            }
            // Skip enormous content lines without wedging subsequent metadata reads.
            if pending.count > 8 * 1024 * 1024 {
                consumed += UInt64(pending.count); pending.removeAll(); cursor.skippingLongLine = true
            }
        }
        cursor.offset += consumed; cursors[file.path] = cursor
    }
    private func parse(_ data: Data, cursor: inout FileCursor) {
        guard let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = entry["type"] as? String, let payload = entry["payload"] as? [String: Any] else { return }
        let date = Self.date(entry["timestamp"]) ?? .distantPast
        if type == "session_meta" {
            guard let id = payload["id"] as? String else { return }
            cursor.sessionID = id; cursor.createdAt = Self.date(payload["timestamp"]) ?? Self.date(entry["timestamp"])
            cursor.child = payload["forked_from_id"] != nil || payload["parent_thread_id"] != nil
                || ((payload["source"] as? [String: Any])?["subagent"] != nil)
            var session = summaries[id] ?? SessionSummary(id: id)
            if let cwd = payload["cwd"] as? String { session.project = URL(fileURLWithPath: cwd).lastPathComponent }
            summaries[id] = session; return
        }
        guard !cursor.sessionID.isEmpty else { return }
        var session = summaries[cursor.sessionID] ?? SessionSummary(id: cursor.sessionID)
        defer { summaries[cursor.sessionID] = session }
        let inherited = cursor.child && date < (cursor.createdAt ?? .distantPast)
        if !inherited { session.lastActivity = max(session.lastActivity, date) }
        if type == "turn_context", !inherited {
            session.model = payload["model"] as? String ?? session.model
            if let cwd = payload["cwd"] as? String { session.project = URL(fileURLWithPath: cwd).lastPathComponent }
        }
        if type == "compacted" {
            let key = cursor.sessionID + ":" + String(date.timeIntervalSince1970)
            if !inherited, compactionIDs.insert(key).inserted { session.compactions += 1 }
        }
        guard type == "event_msg", let event = payload["type"] as? String else { return }
        if event == "token_count", let info = payload["info"] as? [String: Any],
           let total = info["total_token_usage"] as? [String: Any] {
            let cumulative = TokenUsage(total)
            let last = (info["last_token_usage"] as? [String: Any]).map(TokenUsage.init)
            let previous = cursor.previous
            var delta = cumulative.delta(from: previous)
            if cursor.seenSnapshot, cumulative.total < previous.total { delta = last ?? cumulative }
            if !cursor.seenSnapshot, cursor.child, !inherited {
                // Child histories may begin with an inherited cumulative baseline.
                delta = last ?? TokenUsage()
            }
            cursor.previous = cumulative; cursor.seenSnapshot = true
            if inherited { return }
            let fingerprint = [cursor.sessionID, String(date.timeIntervalSince1970), String(cumulative.input), String(cumulative.cached),
                               String(cumulative.output), String(cumulative.total)].joined(separator: ":")
            let id = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
            if delta.total > 0, ledger[id] == nil {
                ledger[id] = UsageDelta(id: id, sessionID: cursor.sessionID, date: date, usage: delta)
            }
            if date >= (session.contextRecordedAt ?? .distantPast) {
                session.cumulative = cumulative; session.lastUsage = last ?? delta
                session.contextWindow = info["model_context_window"] as? Int
                session.contextRecordedAt = date
            }
        } else if !inherited, date >= (session.statusRecordedAt ?? .distantPast) {
            var changed = true
            switch event {
            case "task_started": session.status = .running
            case "task_complete", "task_completed": session.status = .responseReady
            case "turn_aborted": session.status = .interrupted
            case "error": session.status = .failed
            default: changed = false
            }
            if changed { session.statusRecordedAt = date; session.statusFromHook = false }
        }
    }
    public func apply(_ event: HookEvent) {
        var session = summaries[event.sessionID] ?? SessionSummary(id: event.sessionID)
        guard event.date >= (session.statusRecordedAt ?? .distantPast) else { return }
        session.lastActivity = max(session.lastActivity, event.date); session.statusFromHook = true
        session.statusRecordedAt = event.date
        if let project = event.project { session.project = project }
        switch event.event {
        case "SessionStart": session.status = .recorded
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": session.status = .running
        case "PermissionRequest": session.status = .permission
        case "Stop": session.status = .responseReady
        case "Interrupt": session.status = .interrupted
        case "SessionEnd": session.status = .ended
        case "PreCompact": session.status = .compacting
        case "PostCompact": session.status = .running
        default: break
        }
        summaries[event.sessionID] = session
    }
    public func snapshot(warnings: [String] = []) -> LocalSnapshot {
        let totals = Dictionary(grouping: ledger.values, by: \.sessionID).mapValues { $0.reduce(TokenUsage()) { $0 + $1.usage } }
        let sessions = summaries.values.map { s -> SessionSummary in
            var s = s; s.totalOwned = totals[s.id] ?? TokenUsage(); return s
        }.sorted { $0.lastActivity > $1.lastActivity }
        return .init(sessions: sessions, deltas: Array(ledger.values), warnings: warnings)
    }
    private static let dateLock = NSLock()
    private static let fractionalDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let basicDate = ISO8601DateFormatter()
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        dateLock.lock(); defer { dateLock.unlock() }
        return fractionalDate.date(from: string) ?? basicDate.date(from: string)
    }
}

public actor LocalLogStore {
    private let index: LogIndex
    private let cache: URL
    private var hookOffset: UInt64 = 0
    public init(cache: URL) { self.cache = cache; index = LogIndex.load(from: cache) }
    public func scan(home: URL, events: URL) -> LocalSnapshot {
        let snapshot = index.scan(home: home)
        if let handle = try? FileHandle(forReadingFrom: events) {
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            if size < hookOffset { hookOffset = 0 }
            try? handle.seek(toOffset: hookOffset)
            let data = (try? handle.readToEnd()) ?? Data()
            if let last = data.lastIndex(of: 10) {
                for line in data.prefix(through: last).split(separator: 10) {
                    if let event = try? JSONDecoder().decode(HookEvent.self, from: Data(line)) { index.apply(event) }
                }
                hookOffset += UInt64(last + 1)
            }
        }
        try? index.save(to: cache)
        return index.snapshot(warnings: snapshot.warnings)
    }
}
