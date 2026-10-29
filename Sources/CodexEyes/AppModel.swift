import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import CoreServices
import CodexEyesCore

@MainActor final class AppModel: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            L10n.language = preferences.language
            if preferences.demo { return }
            var stored = preferences; stored.demo = false
            if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: "preferences.v1") }
            if preferences.demo != oldValue.demo { changeMode() }
        }
    }
    @Published var accounts: [Account] = []
    @Published var identity = IdentityState()
    @Published var local = LocalSnapshot(sessions: [], deltas: [], warnings: [])
    @Published var activities: [String: AccountActivityState] = [:]
    @Published var busy = false
    @Published var message: String?
    @Published var panelVisible = false
    @Published var pinned = false
    @Published var hooksInstalled = false
    @Published var hooksReceived = false
    @Published var lastCheck: Date?
    @Published var notificationAuthorization: UNAuthorizationStatus?
    @Published var selectedSessionID: String?
    var onSettings: (() -> Void)?
    var onDetails: (() -> Void)?
    var onPanelHeight: ((CGFloat) -> Void)?
    var onViewAccount: ((String) -> Void)?
    var onRequestSwitch: ((String) -> Void)?
    var onPin: (() -> Void)?
    var onQuit: (() -> Void)?
    var onShortcutChange: ((PanelShortcut) -> String?)?
    var onShortcutRecording: ((Bool) -> Void)?
    private let backend: CLIAccountBackend?
    private var logStore: LocalLogStore?
    private let cache = EyesPaths.support.appendingPathComponent("accounts.json")
    private let activityCache = EyesPaths.support.appendingPathComponent("account-activity.json")
    private var activityBackend: CodexAccountActivityBackend?
    private var generation = 0
    private var timer: Timer?
    private var resetTimer: Timer?
    private var resetChecks: Set<String> = []
    private var watcher: FileWatch?
    private var scanTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var notificationKeys: [String: Double] = [:]
    private var previousAvailability: [String: Availability] = [:]
    private var previousTaskStatus: [String: SessionStatus] = [:]
    private var synchronizedLoginStamp: String?

    init(demo: Bool = false, previewLanguage: AppLanguage? = nil) {
        var loaded = (UserDefaults.standard.data(forKey: "preferences.v1").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }) ?? Preferences()
        if demo, let previewLanguage { loaded.language = previewLanguage }
        loaded.demo = demo // Preview is explicit and process-local; never restore a saved demo mode.
        preferences = loaded
        L10n.language = loaded.language
        notificationKeys = (UserDefaults.standard.dictionary(forKey: "notificationLedger.v1") as? [String: Double] ?? [:])
            .filter { Date().timeIntervalSince1970 - $0.value < 8 * 86400 }
        backend = EyesPaths.helper.map { CLIAccountBackend(executable: $0, codexHome: EyesPaths.codexHome) }
        activityBackend = EyesPaths.codexCLI.map { CodexAccountActivityBackend(executable: $0, codexHome: EyesPaths.codexHome) }
        if !loaded.demo, let data = try? Data(contentsOf: cache), let list = try? JSONDecoder().decode(AccountList.self, from: data) {
            accounts = list.accounts.filter { $0.usage?.source != "demo" }; identity.reconcile(AccountList(activeAccountKey: list.activeAccountKey, accounts: accounts))
        }
        if !loaded.demo, let data = try? Data(contentsOf: activityCache),
           let saved = try? JSONDecoder().decode([String: AccountActivityState].self, from: data) {
            activities = saved.filter { key, _ in accounts.contains { $0.id == key } }
        }
        if loaded.demo { setDemo() }
    }
    var viewed: Account? { orderedAccounts.first { $0.id == identity.viewedAccountID } ?? orderedAccounts.first }
    var orderedAccounts: [Account] {
        accounts.sorted { a, b in
            let ai = preferences.order.firstIndex(of: a.id) ?? Int.max
            let bi = preferences.order.firstIndex(of: b.id) ?? Int.max
            return ai == bi ? a.id < b.id : ai < bi
        }
    }
    var selectedSession: SessionSummary? {
        let id = preferences.pinnedSession ?? selectedSessionID
        return local.usageSessions.first { $0.id == id } ?? local.usageSessions.first
    }
    var configuredName: String {
        accounts.first { $0.id == identity.configuredAccountID }.map(name) ?? L("未识别")
    }
    var activityTotals: AccountActivityTotals {
        AccountActivityTotals(accountIDs: accounts.map(\.id), states: activities)
    }
    func name(_ account: Account) -> String {
        if let note = preferences.notes[account.id], !note.isEmpty { return note }
        if preferences.privacy { return L("账号 \((orderedAccounts.firstIndex { $0.id == account.id } ?? 0) + 1)") }
        return account.displayName
    }
    func start() {
        guard !preferences.demo else { return }
        try? FileManager.default.createDirectory(at: EyesPaths.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        hooksInstalled = HookConfiguration.installed(home: EyesPaths.codexHome)
        Task { await refresh() }
        Task { await scan() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        resetTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkResets()
                await self?.syncConfiguredLoginIfChanged()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh(); await self?.scan() }
        }
        watcher = FileWatch(paths: [EyesPaths.codexHome.path, EyesPaths.support.path]) { [weak self] in
            Task { @MainActor in self?.scheduleScan() }
        }
    }
    private func stop() {
        timer?.invalidate(); timer = nil; resetTimer?.invalidate(); resetTimer = nil
        watcher = nil; scanTask?.cancel()
        if let observer = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer); wakeObserver = nil }
    }
    private func changeMode() {
        generation += 1; stop(); message = nil; busy = false; lastCheck = nil
        logStore = nil; synchronizedLoginStamp = nil
        accounts = []; activities = [:]; identity = IdentityState(); local = .init(sessions: [], deltas: [], warnings: [])
        previousAvailability = [:]; previousTaskStatus = [:]; resetChecks = []
        if preferences.demo { setDemo() } else { start() }
    }
    private func setDemo() {
        notificationAuthorization = .notDetermined
        let list = DemoData.accounts(); accounts = list.accounts; identity.reconcile(list); identity.panelOpened()
        local = .demo(); lastCheck = Date()
        activities = Dictionary(uniqueKeysWithValues: list.accounts.enumerated().map { index, account in
            let days = (0..<10).map { offset in
                AccountActivityDay(startDate: String(format: "2026-10-%02d", 18 + offset), tokens: (index + 1) * (offset + 3) * 100000)
            }
            return (account.id, AccountActivityState(snapshot: .init(summary: .init(lifetimeTokens: index == 0 ? 24_800_000 : 15_200_000,
                                                                                    peakDailyTokens: 2_400_000), dailyUsageBuckets: days)))
        })
    }
    func opened() {
        panelVisible = true; identity.panelOpened()
        if !preferences.demo, Date().timeIntervalSince(lastCheck ?? .distantPast) > 60 { Task { await refresh() } }
    }
    func refresh() async {
        guard !preferences.demo else { setDemo(); return }
        guard !busy else { return }
        guard let backend else { message = L("尚未找到内置账号工具，请使用打包脚本构建 App。"); return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let loginStamp = configuredLoginStamp()
            var list = try await backend.list(remote: true)
            guard ticket == generation else { return }
            let now = Date()
            for i in list.accounts.indices {
                let account = list.accounts[i]
                if account.usage?.refresh?.status == "ok", account.usage?.refresh?.method == "api" {
                    list.accounts[i].lastConfirmedAt = now
                } else {
                    list.accounts[i].lastConfirmedAt = accounts.first { $0.id == account.id }?.lastConfirmedAt
                }
            }
            apply(list); synchronizedLoginStamp = loginStamp; lastCheck = now; message = nil
            try persist(list)
            checkAccountNotifications()
        } catch {
            guard ticket == generation else { return }
            // A failed group refresh invalidates green status, while retaining displayed cached values.
            for i in accounts.indices { accounts[i].usage?.refresh = .init(status: "error") }
            try? persist(AccountList(activeAccountKey: identity.configuredAccountID, accounts: accounts))
            message = error.localizedDescription
        }
        guard ticket == generation else { return }
        await refreshActivities(ticket: ticket)
    }
    private func refreshActivities(ticket: Int) async {
        if activityBackend == nil {
            activityBackend = EyesPaths.codexCLI.map { CodexAccountActivityBackend(executable: $0, codexHome: EyesPaths.codexHome) }
        }
        for id in accounts.map(\.id) {
            guard ticket == generation else { return }
            do {
                guard let activityBackend else { throw EyesError.message(L("账号统计需要已安装的 Codex CLI 或 ChatGPT 桌面客户端。")) }
                let snapshot = try await activityBackend.read(accountID: id)
                guard ticket == generation, accounts.contains(where: { $0.id == id }) else { return }
                activities[id] = .init(snapshot: snapshot)
            } catch {
                guard ticket == generation else { return }
                activities[id] = .init(snapshot: activities[id]?.snapshot, error: error.localizedDescription)
            }
        }
        guard ticket == generation else { return }
        try? persistActivities()
    }
    private func apply(_ list: AccountList) {
        accounts = list.accounts; identity.reconcile(list)
        activities = activities.filter { key, _ in list.accounts.contains { $0.id == key } }
    }
    private func persistActivities() throws {
        try FileManager.default.createDirectory(at: EyesPaths.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(activities).write(to: activityCache, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activityCache.path)
    }
    private func persist(_ list: AccountList) throws {
        try FileManager.default.createDirectory(at: EyesPaths.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(list).write(to: cache, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
    }
    private func checkResets() {
        guard !preferences.demo, !busy else { return }
        let now = Date().timeIntervalSince1970
        let due = accounts.flatMap { a in [a.usage?.primary, a.usage?.secondary].compactMap { $0 }.compactMap { q -> String? in
            guard let reset = q.resetsAt, reset <= now else { return nil }
            return a.id + ":" + String(reset)
        }}
        // Each expired snapshot gets one immediate refresh; the normal timer supplies backoff.
        if due.contains(where: { !resetChecks.contains($0) }) {
            resetChecks.formUnion(due); Task { await refresh() }
        }
    }
    func view(_ id: String) { identity.view(id) }
    func requestSwitch(_ id: String) { onRequestSwitch?(id) }
    func prepareLoginSwitch(_ id: String) throws -> Bool {
        guard preferences.allowSwitching else { throw EyesError.message(L("请先在账号设置中允许切换登录账号。")) }
        guard !preferences.demo, backend != nil else { throw EyesError.message(L("当前无法更改登录配置。")) }
        guard !busy else { throw EyesError.message(L("账号正在刷新，请稍后再试。")) }
        guard accounts.contains(where: { $0.id == id }), identity.configuredAccountID != id else {
            throw EyesError.message(L("账号状态已变化，请重新选择。"))
        }
        return try LoginSwitchPolicy.needsConfirmation(skipConfirmation: preferences.skipSwitchConfirmation,
                                                       checkExited: RuntimeGuard.requireExited)
    }
    @discardableResult
    func perform(_ operation: String, id: String? = nil) async -> Bool {
        guard !busy else { message = L("账号正在刷新，请稍后再试。"); return false }
        guard !preferences.demo, let backend else { message = L("当前无法更改登录配置。"); return false }
        guard operation != "switch" || preferences.allowSwitching else {
            message = L("请先在账号设置中允许切换登录账号。"); return false
        }
        // Recheck immediately before the helper call, including after a confirmation sheet.
        do { try RuntimeGuard.requireExited() } catch { message = error.localizedDescription; return false }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        var succeeded = false
        do {
            switch operation {
            case "switch":
                guard let id, accounts.contains(where: { $0.id == id }) else { throw EyesError.message(L("账号状态已变化，请重新选择。")) }
                try await backend.activate(id: id)
            case "remove": if let id { try await backend.remove(id: id) }
            case "login": try await backend.login()
            default: throw EyesError.message(L("不支持的账号操作。"))
            }
            let list = try await backend.list(remote: false)
            guard ticket == generation else { return false }
            apply(list); try persist(list)
            if operation == "switch" {
                guard list.activeAccountKey == id else { throw EyesError.message(L("配置账号尚未核验，请刷新确认。")) }
                identity.viewedAccountID = id
                message = L("配置已切换，下次启动客户端生效。")
            } else { message = operation == "login" ? L("账号已添加，配置以列表标记为准。") : L("账号已移除。") }
            succeeded = true
        } catch {
            guard ticket == generation else { return false }
            if let list = try? await backend.list(remote: false), ticket == generation { apply(list) }
            message = error.localizedDescription
        }
        if ticket == generation { await refreshActivities(ticket: ticket) }
        return succeeded
    }
    func move(_ account: Account, by delta: Int) {
        var ids = orderedAccounts.map(\.id)
        guard let index = ids.firstIndex(of: account.id), ids.indices.contains(index + delta) else { return }
        ids.swapAt(index, index + delta); preferences.order = ids
    }
    private func scheduleScan() {
        guard !preferences.demo else { return }
        scanTask?.cancel()
        scanTask = Task { try? await Task.sleep(nanoseconds: 700_000_000); if !Task.isCancelled { await scan(); await syncConfiguredLoginIfChanged() } }
    }
    /// Observe the login written by the user's client; list synchronizes its own account registry.
    /// Never run login/switch or change auth.json in response to a filesystem notification.
    private func configuredLoginStamp() -> String {
        let file = EyesPaths.codexHome.appendingPathComponent("auth.json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { return "missing" }
        return [String((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0),
                String((attributes[.size] as? NSNumber)?.uint64Value ?? 0),
                String((attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)].joined(separator: ":")
    }
    func syncConfiguredLoginIfChanged() async {
        guard !preferences.demo, !busy, let backend else { return }
        let stamp = configuredLoginStamp()
        guard stamp != synchronizedLoginStamp else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            var list = try await backend.list(remote: false)
            guard ticket == generation else { return }
            for index in list.accounts.indices {
                if let previous = accounts.first(where: { $0.id == list.accounts[index].id }) {
                    list.accounts[index].usage = previous.usage ?? list.accounts[index].usage
                    list.accounts[index].lastConfirmedAt = previous.lastConfirmedAt
                }
            }
            apply(list); try persist(list)
            synchronizedLoginStamp = stamp
            Task { [weak self] in await self?.refresh() }
        } catch {
            guard ticket == generation else { return }
            message = L("未能同步本机登录信息，请稍后刷新。")
        }
    }
    func scan() async {
        guard !preferences.demo else { return }
        let ticket = generation
        if logStore == nil { logStore = LocalLogStore(cache: EyesPaths.support.appendingPathComponent("log-index.json")) }
        guard let logStore else { return }
        let snapshot = await logStore.scan(home: EyesPaths.codexHome, events: EyesPaths.support.appendingPathComponent("events.jsonl"))
        guard ticket == generation else { return }
        local = snapshot
        hooksInstalled = HookConfiguration.installed(home: EyesPaths.codexHome)
        hooksReceived = snapshot.sessions.contains { $0.statusFromHook }
        for session in snapshot.sessions {
            if let previous = previousTaskStatus[session.id], previous != session.status,
               preferences.notifyTasks, [.permission, .failed, .responseReady].contains(session.status) {
                notify(key: "task:\(session.id):\(session.status.rawValue):\(session.lastActivity.timeIntervalSince1970)",
                       title: session.status.label, body: preferences.privacy ? L("本机会话有新状态") : session.displayTitle)
            }
            previousTaskStatus[session.id] = session.status
        }
    }
    func toggleHooks(_ enabled: Bool) {
        guard !preferences.demo else { message = L("演示模式不会修改 Hooks。"); return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexEyesHook")
        guard !enabled || FileManager.default.isExecutableFile(atPath: helper.path) else { message = L("请从打包后的 App 连接 Hooks。"); return }
        do {
            try HookConfiguration.update(home: EyesPaths.codexHome, helper: helper, enabled: enabled)
            hooksInstalled = enabled
            message = enabled ? L("Hooks 已配置。请在 Codex 的 /hooks 中检查并信任，再运行一轮任务验证。") : L("已移除 Codex Eyes 的 Hooks，其他配置保留。")
        } catch { message = error.localizedDescription }
    }
    func requestNotifications() {
        guard !preferences.demo, Bundle.main.bundleIdentifier != nil else { return }
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch { message = L("无法申请通知权限，请在系统设置中检查。") }
            await refreshNotificationAuthorization()
        }
    }
    func refreshNotificationAuthorization() async {
        guard !preferences.demo, Bundle.main.bundleIdentifier != nil else { return }
        notificationAuthorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func openNotificationSettings() {
        guard let id = Bundle.main.bundleIdentifier,
              let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=" + id) else { return }
        NSWorkspace.shared.open(url)
    }
    private func checkAccountNotifications() {
        for account in accounts {
            let status = account.availability()
            if preferences.notifyBackup, account.id != identity.configuredAccountID,
               previousAvailability[account.id] != nil, previousAvailability[account.id] != .available, status == .available {
                notify(key: "backup:\(account.id):\(Int(Date().timeIntervalSince1970 / 300))", title: L("其他账号已恢复可用"), body: name(account))
            }
            if preferences.notifyQuota, status == .available || status == .limited {
                for q in [account.usage?.primary, account.usage?.secondary].compactMap({ $0 }) where q.remaining <= 20 {
                    notify(key: "quota:\(account.id):\(q.label):\(q.resetsAt ?? 0)", title: L("Codex 额度偏低"), body: L("\(name(account)) · \(q.label) 剩余 \(Int(q.remaining))%"))
                }
            }
            previousAvailability[account.id] = status
        }
    }
    private func notify(key: String, title: String, body: String) {
        guard !preferences.demo, Bundle.main.bundleIdentifier != nil, notificationKeys[key] == nil else { return }
        notificationKeys[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(notificationKeys, forKey: "notificationLedger.v1")
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }
    func openClient() {
        let paths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
        if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }
    func updateShortcut(_ shortcut: PanelShortcut) -> String? {
        guard shortcut.isValid else { return L("请使用包含 ⌘ 或 ⌃ 的快捷键，避开常用系统组合。") }
        guard shortcut != preferences.shortcut else { return nil }
        if let error = onShortcutChange?(shortcut) { return error }
        preferences.shortcut = shortcut
        return nil
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { message = L("开机启动设置失败：\(error.localizedDescription)") }
    }
}

final class FileWatch {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void
    init(paths: [String], callback: @escaping () -> Void) {
        self.callback = callback
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else { return }
            let strings = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let rescan = (0..<count).contains { flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
            if strings.contains(where: { $0.hasSuffix("auth.json") || $0.hasSuffix(".jsonl") || $0.contains("/sessions") || $0.contains("/archived_sessions") }) || count == 0 || rescan {
                Unmanaged<FileWatch>.fromOpaque(info).takeUnretainedValue().callback()
            }
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    deinit { if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
}
