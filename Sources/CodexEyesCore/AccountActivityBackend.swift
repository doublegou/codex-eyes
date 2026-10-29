import Foundation
import Darwin

public protocol AccountActivityBackend: Sendable {
    func read(accountID: String) async throws -> AccountActivity
}

/// Each read owns a short-lived app-server and a private auth snapshot. Never switches the user's login.
public final class CodexAccountActivityBackend: AccountActivityBackend, @unchecked Sendable {
    private let executable: URL
    private let home: URL
    private let temporaryRoot: URL
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "app.codexeyes.account-activity", qos: .utility)
    public init(executable: URL, codexHome: URL, temporaryRoot: URL = FileManager.default.temporaryDirectory, timeout: TimeInterval = 20) {
        self.executable = executable; home = codexHome; self.temporaryRoot = temporaryRoot; self.timeout = timeout
    }
    public func read(accountID: String) async throws -> AccountActivity {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.readSynchronously(accountID: accountID)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func readSynchronously(accountID: String) throws -> AccountActivity {
        let auth = try SavedAccountAuth.readOnlyCopy(SavedAccountAuth.load(accountID: accountID, home: home))
        let directory = temporaryRoot.appendingPathComponent("codexeyes-activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("auth.json")
        guard FileManager.default.createFile(atPath: file.path, contents: auth, attributes: [.posixPermissions: 0o600]) else {
            throw EyesError.message(L("无法准备账号统计查询。"))
        }
        try Data("cli_auth_credentials_store = \"file\"\n[analytics]\nenabled = false\n".utf8)
            .write(to: directory.appendingPathComponent("config.toml"))
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OPENAI_API_KEY"); environment.removeValue(forKey: "CODEX_API_KEY")
        environment["CODEX_HOME"] = directory.path
        environment["CODEX_SQLITE_HOME"] = directory.path
        environment = environment.merging(NetworkEnvironment.systemProxy()) { _, value in value }
        let session = try ActivityRPCSession(executable: executable, directory: directory, environment: environment, timeout: timeout)
        defer { session.close() }
        _ = try session.request("initialize", params: ["clientInfo": ["name": "codex_eyes", "title": "Codex Eyes", "version": "1.0.0"],
                                                       "capabilities": ["experimentalApi": false]])
        try session.notify("initialized")
        let account = try session.request("account/read", params: ["refreshToken": false])
        guard let object = try? JSONSerialization.jsonObject(with: account) as? [String: Any],
              let identity = object["account"] as? [String: Any], identity["type"] as? String == "chatgpt" else {
            throw EyesError.message(L("此登录方式不支持账号活动统计。"))
        }
        return try AccountActivity.decodeReply(session.request("account/usage/read"))
    }
}

enum SavedAccountAuth {
    /// A read-only child must not rotate the original OAuth session's refresh token.
    static func readOnlyCopy(_ data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var tokens = object["tokens"] as? [String: Any] else { throw EyesError.message(L("登录凭据格式不兼容。")) }
        guard tokens["refresh_token"] != nil else { return data }
        tokens["refresh_token"] = ""
        object["tokens"] = tokens
        return try JSONSerialization.data(withJSONObject: object)
    }
    static func key(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any], let token = tokens["id_token"] as? String else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let decoded = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any],
              let user = (auth["chatgpt_user_id"] ?? auth["user_id"]) as? String,
              let account = (tokens["account_id"] ?? auth["chatgpt_account_id"]) as? String,
              !user.isEmpty, !account.isEmpty else { return nil }
        return user + "::" + account
    }
    static func load(accountID: String, home: URL) throws -> Data {
        let saved = ((try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent("accounts"),
                         includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".auth.json") }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in [home.appendingPathComponent("auth.json")] + saved {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
                  let data = try? Data(contentsOf: file), key(in: data) == accountID else { continue }
            return data
        }
        throw EyesError.message(L("未找到此账号的本地 ChatGPT 登录凭据。"))
    }
}

/// Bounded synchronous JSON-RPC on a utility queue; no shell, diagnostics or raw auth output.
private final class ActivityRPCSession {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private let ended = DispatchSemaphore(value: 0)
    private let timeout: TimeInterval
    private var buffer = Data()
    private var nextID = 0
    init(executable: URL, directory: URL, environment: [String: String], timeout: TimeInterval) throws {
        self.timeout = timeout
        process.executableURL = executable; process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = directory; process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.terminationHandler = { [ended] _ in ended.signal() }
        do { try process.run() } catch { throw EyesError.message(L("无法启动 Codex 账号统计服务，请检查 Codex 安装。")) }
    }
    func notify(_ method: String) throws { try write(["method": method]) }
    func request(_ method: String, params: [String: Any]? = nil) throws -> Data {
        nextID += 1; let id = nextID
        var object: [String: Any] = ["id": id, "method": method]
        if let params { object["params"] = params }
        try write(object)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
                guard let reply = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                guard reply["id"] as? Int == id, reply["method"] == nil else { continue }
                if let error = reply["error"] as? [String: Any] {
                    let code = error["code"] as? Int
                    throw EyesError.message(code == -32601 ? L("当前 Codex 版本不支持账号统计，请更新 Codex。") : L("账号统计查询失败，请稍后刷新。"))
                }
                guard let result = reply["result"] as? [String: Any] else { throw EyesError.message(L("账号统计暂不可用。")) }
                return try JSONSerialization.data(withJSONObject: result)
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw EyesError.message(L("账号统计查询超时，已保留上次结果。")) }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, Double(Int32.max))))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { throw EyesError.message(L("账号统计查询超时，已保留上次结果。")) }
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw EyesError.message(L("Codex 统计服务已退出，请重新刷新。")) }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 2 * 1024 * 1024 else { throw EyesError.message(L("账号统计响应超出大小限制。")) }
        }
    }
    private func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw EyesError.message(L("无法向 Codex 统计服务发送请求。")) }
    }
    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            if ended.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = ended.wait(timeout: .now() + 2)
            }
        }
        try? output.fileHandleForReading.close()
    }
}
