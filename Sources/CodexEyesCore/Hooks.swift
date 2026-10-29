import Foundation
import Darwin

public struct HookEvent: Codable, Sendable {
    public var sessionID: String
    public var event: String
    public var date: Date
    public var project: String?
    public init?(input: [String: Any], date: Date = Date()) {
        guard let id = input["session_id"] as? String, !id.isEmpty,
              let name = input["hook_event_name"] as? String,
              HookConfiguration.events.contains(name) else { return nil }
        sessionID = String(id.prefix(200)); event = name; self.date = date
        if let cwd = input["cwd"] as? String { project = String(URL(fileURLWithPath: cwd).lastPathComponent.prefix(200)) }
    }
}

public enum HookConfiguration {
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                                "Stop", "Interrupt", "SessionEnd", "PreCompact", "PostCompact"]
    public static let marker = "Codex Eyes · local activity"
    public static func containsOwnHandler(_ handler: [String: Any]) -> Bool {
        handler["statusMessage"] as? String == marker && (handler["command"] as? String)?.contains("CodexEyesHook") == true
    }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func update(home: URL, helper: URL, enabled: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let lock = open(home.appendingPathComponent(".codexeyes-hooks.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw EyesError.message(L("无法锁定 Hooks 配置。")) }
        defer { flock(lock, LOCK_UN); close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw EyesError.message(L("无法锁定 Hooks 配置。")) }
        let file = home.appendingPathComponent("hooks.json")
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EyesError.message(L("hooks.json 格式无法识别，原文件未修改。"))
            }
            root = object
            let backup = home.appendingPathComponent("hooks.json.codexeyes-backup-\(UUID().uuidString)")
            try data.write(to: backup, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        if root["hooks"] != nil && !(root["hooks"] is [String: Any]) { throw EyesError.message(L("Hooks 配置格式不兼容。")) }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            if hooks[event] != nil && !(hooks[event] is [[String: Any]]) { throw EyesError.message(L("Hooks 事件格式不兼容。")) }
            var groups: [[String: Any]] = []
            for var group in hooks[event] as? [[String: Any]] ?? [] {
                guard let handlers = group["hooks"] as? [[String: Any]] else { groups.append(group); continue }
                let other = handlers.filter { !containsOwnHandler($0) }
                if !other.isEmpty { group["hooks"] = other; groups.append(group) }
                else if handlers.isEmpty { groups.append(group) }
            }
            if enabled {
                groups.append(["hooks": [["type": "command", "command": shellQuote(helper.path),
                                           "statusMessage": marker, "timeout": 1]]])
            }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public static func installed(home: URL) -> Bool {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("hooks.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.contains { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: containsOwnHandler)
            }
        }
    }
}

public enum HookRecorder {
    public static func record(_ event: HookEvent, directory: URL = EyesPaths.support) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = open(directory.appendingPathComponent("events.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { return }
        defer { flock(lock, LOCK_UN); close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { return }
        let file = directory.appendingPathComponent("events.jsonl")
        if let attrs = try? fm.attributesOfItem(atPath: file.path), let bytes = attrs[.size] as? NSNumber,
           bytes.intValue > 8 * 1024 * 1024 {
            let previous = directory.appendingPathComponent("events.previous.jsonl")
            try? fm.removeItem(at: previous); try fm.moveItem(at: file, to: previous)
        }
        let fd = open(file.path, O_CREAT | O_WRONLY | O_APPEND, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var data = try JSONEncoder().encode(event); data.append(10)
        try data.withUnsafeBytes { bytes in
            guard write(fd, bytes.baseAddress, bytes.count) == bytes.count else {
                throw EyesError.message(L("写入本地事件失败。"))
            }
        }
    }
}
