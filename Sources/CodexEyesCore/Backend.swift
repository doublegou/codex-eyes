import Foundation
import Darwin

public enum EyesError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

public struct ProcessOutput: Sendable { public let data: Data; public let exitCode: Int32 }

/// One queue for all account operations. Actor reentrancy must not overlap CLI invocations.
public final class CommandRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.codexeyes.account-commands", qos: .utility)
    public init() {}
    public func run(_ executable: URL, arguments: [String], environment: [String: String] = [:],
                    timeout: TimeInterval = 60) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try Self.execute(executable, arguments: arguments,
                                                                    environment: environment, timeout: timeout))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func execute(_ executable: URL, arguments: [String], environment: [String: String],
                                timeout: TimeInterval) throws -> ProcessOutput {
        let process = Process(), output = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in value }
        process.standardOutput = output
        // Never retain unstructured diagnostics: upstream may include account identifiers.
        process.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        // Read concurrently so a full stdout pipe cannot deadlock waitUntilExit.
        let reader = DispatchGroup()
        let box = DataBox()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            var collected = Data()
            while true {
                let chunk = output.fileHandleForReading.readData(ofLength: 65536)
                if chunk.isEmpty { break }
                if collected.count < 16 * 1024 * 1024 { collected.append(chunk) }
            }
            box.data = collected; reader.leave()
        }
        if completed.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if completed.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            // Do not wait on inherited stdout descriptors from a surviving descendant.
            throw EyesError.message(L("操作超时，请刷新确认状态；没有自动重试。"))
        }
        guard reader.wait(timeout: .now() + 3) == .success else {
            throw EyesError.message(L("辅助程序输出未结束，请重新检查状态。"))
        }
        return ProcessOutput(data: box.data, exitCode: process.terminationStatus)
    }
}
private final class DataBox: @unchecked Sendable { var data = Data() }

public protocol AccountBackend: Sendable {
    func list(remote: Bool) async throws -> AccountList
    func activate(id: String) async throws
    func remove(id: String) async throws
    func login() async throws
}

public final class CLIAccountBackend: AccountBackend, @unchecked Sendable {
    public let executable: URL
    private let runner: CommandRunner
    private let environment: [String: String]
    private let codexHome: URL
    public init(executable: URL, codexHome: URL, runner: CommandRunner = CommandRunner()) {
        self.executable = executable; self.runner = runner; self.codexHome = codexHome
        var path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let bundledCodex = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS"
        if FileManager.default.fileExists(atPath: bundledCodex + "/codex") { path = bundledCodex + ":" + path }
        if FileManager.default.fileExists(atPath: "/Applications/Codex.app/Contents/Resources/codex") {
            path = "/Applications/Codex.app/Contents/Resources:" + path
        }
        environment = ["CODEX_HOME": codexHome.path, "PATH": path, "NO_COLOR": "1"]
    }
    public func list(remote: Bool) async throws -> AccountList {
        let result = try await invoke(["list", remote ? "--api" : "--skip-api", "--json"])
        var list = try JSONDecoder().decode(AccountList.self, from: result)
        guard list.schemaVersion == 1 else { throw EyesError.message(L("账号工具接口版本不兼容。")) }
        let names = LocalProfileNames.load(home: codexHome)
        for i in list.accounts.indices { list.accounts[i].profileName = names[list.accounts[i].id] }
        return list
    }
    public func activate(id: String) async throws { _ = try await invoke(["switch", id, "--json"]) }
    public func remove(id: String) async throws { _ = try await invoke(["remove", id, "--json"]) }
    public func login() async throws {
        let output = try await runner.run(executable, arguments: ["login"], environment: childEnvironment, timeout: 300)
        guard output.exitCode == 0 else { throw EyesError.message(L("登录未完成，请重试或在终端完成 codex-auth login。")) }
    }
    private func invoke(_ args: [String]) async throws -> Data {
        let output = try await runner.run(executable, arguments: args, environment: childEnvironment)
        if let object = try? JSONSerialization.jsonObject(with: output.data) as? [String: Any],
           let error = object["error"] as? [String: Any] {
            let code = error["code"] as? String ?? "unknown"
            throw EyesError.message(L("账号操作失败（\(code)），请刷新检查。"))
        }
        guard output.exitCode == 0 else { throw EyesError.message(L("账号工具未成功完成，请刷新检查。")) }
        return output.data
    }
    private var childEnvironment: [String: String] {
        environment.merging(NetworkEnvironment.systemProxy()) { _, value in value }
    }
}

/// Skipping the explanatory confirmation must never bypass the exit check.
public enum LoginSwitchPolicy {
    public static func needsConfirmation(skipConfirmation: Bool, checkExited: () throws -> Void) throws -> Bool {
        try checkExited()
        return !skipConfirmation
    }
}

public enum RuntimeGuard {
    public static func blockingProcesses(in listing: String) -> [String] {
        listing.split(separator: "\n").compactMap { line in
            let fields = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard fields.count == 2 else { return nil }
            let path = String(fields[1]), name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            if name == "codex" || name == "codext" || name == "chatgpt" || name == "codex-app-server"
                || path.contains("/ChatGPT.app/") || path.contains("/Codex.app/") {
                return name
            }
            return nil
        }
    }
    public static func requireExited() throws {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, let listing = String(data: data, encoding: .utf8), !listing.isEmpty else {
            throw EyesError.message(L("无法确认客户端退出状态，暂不允许更改登录。"))
        }
        guard blockingProcesses(in: listing).isEmpty else {
            throw EyesError.message(L("请先完全退出 ChatGPT / Codex 及相关 Codex 后台进程。关闭窗口不等于退出。"))
        }
    }
}

public enum EyesPaths {
    public static var codexHome: URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: NSString(string: home).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexEyes")
    }
    public static var helper: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codex-auth")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("ThirdParty/bin/\(ProcessInfo.processInfo.machineArchitecture)/codex-auth")
        return FileManager.default.isExecutableFile(atPath: development.path) ? development : nil
    }
    public static var codexCLI: URL? {
        let known = ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                     "/Applications/Codex.app/Contents/Resources/codex"]
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":").filter { !$0.isEmpty }.map { String($0) + "/codex" }
        return (known + path).first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}
private extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
