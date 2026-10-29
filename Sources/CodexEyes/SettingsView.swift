import SwiftUI
import ServiceManagement
import UserNotifications
import CodexEyesCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pending: Account?
    @State private var showRemove = false
    @State private var showAddAccount = false
    @State private var tab: Int? = 1
    init(model: AppModel, initialTab: Int = 1) {
        self.model = model; _tab = State(initialValue: initialTab)
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $tab) {
                Label(L("账号"), systemImage: "person.crop.circle").tag(1)
                Label(L("通用"), systemImage: "gearshape").tag(0)
                Label(L("通知"), systemImage: "bell").tag(2)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
            .navigationTitle(L("设置"))
        } detail: {
            Group {
                switch tab {
                case 1: accounts
                case 2: notifications
                default: general
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .navigationTitle([0: L("通用"), 1: L("账号"), 2: L("通知")][tab ?? 0] ?? L("设置"))
            .toolbar {
                if tab == 1 {
                    if #available(macOS 26.0, *) {
                        ToolbarItem(placement: .primaryAction) { addAccountButton }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .primaryAction) { addAccountButton }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 480)
        .tint(EyesTheme.accent)
        .sheet(isPresented: $showAddAccount) { AddAccountView(model: model) }
        .alert(L("从账号工具中移除？"), isPresented: $showRemove) {
            Button(L("取消"), role: .cancel) {}
            Button(L("移除"), role: .destructive) { if let id = pending?.id { Task { await model.perform("remove", id: id) } } }
        } message: { Text(L("这将移除 \(pending.map(model.name) ?? L("该账号")) 的本地保存记录。请先退出客户端。")) }

    }
    private var addAccountButton: some View {
        Button { showAddAccount = true } label: {
            Label(L("添加账号"), systemImage: "person.badge.plus")
        }.labelStyle(.iconOnly).buttonStyle(.borderless).tint(.primary).help(L("添加账号"))
    }

    private var general: some View {
        Form {
            Section(L("显示")) {
                HStack {
                    Text(L("语言"))
                    Spacer()
                    SettingsPicker(title: L("语言"), selection: $model.preferences.language,
                                   options: [(.system, L("跟随系统")), (.simplifiedChinese, "简体中文"), (.english, "English")]).fixedSize().frame(height: 22)
                }
                HStack {
                    Text(L("外观"))
                    Spacer()
                    SettingsPicker(title: L("外观"), selection: $model.preferences.appearance,
                                   options: [(.system, L("跟随系统")), (.light, L("浅色")), (.dark, L("深色"))]).fixedSize().frame(height: 22)
                }
                Toggle(L("隐藏邮箱和会话名称"), isOn: $model.preferences.privacy)
                Toggle(L("减少动画"), isOn: $model.preferences.reducedMotion)
            }
            Section {
                Toggle(L("开机启动"), isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: model.setLaunchAtLogin))
                ShortcutSetting(model: model)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("菜单栏额度"))
                    Text(L("优先显示5小时剩余额度；无5小时限制时显示每周额度。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(L("运行"))
            } footer: {
                Text(L("版本") + " " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }.formStyle(.grouped).toggleStyle(.switch)
    }

    private var accounts: some View {
        Form {
            Section {
                Toggle(isOn: $model.preferences.allowSwitching) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("允许切换登录账号"))
                        Text(L("查看额度只切换看板。更换登录需先退出客户端及相关后台进程，下次启动生效。"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(model.orderedAccounts) { account in
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        AccountAvatar(name: model.name(account))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(model.name(account)).font(.headline)
                                if account.id == model.identity.configuredAccountID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                        .help(L("当前登录配置")).accessibilityLabel(L("当前登录配置"))
                                }
                            }
                            Text(model.preferences.privacy ? L("邮箱已隐藏") : (account.email ?? ""))
                                .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Button { model.move(account, by: -1) } label: { Image(systemName: "arrow.up").fontWeight(.medium).frame(width: 16, height: 18) }
                                .help(L("上移账号")).accessibilityLabel(L("上移账号"))
                                .disabled(model.orderedAccounts.first?.id == account.id)
                            Button { model.move(account, by: 1) } label: { Image(systemName: "arrow.down").fontWeight(.medium).frame(width: 16, height: 18) }
                                .help(L("下移账号")).accessibilityLabel(L("下移账号"))
                                .disabled(model.orderedAccounts.last?.id == account.id)
                        }.buttonStyle(.bordered).controlSize(.small).fixedSize()
                    }.padding(.vertical, 4)
                    LabeledContent(L("套餐"), value: account.plan ?? L("未提供"))
                    LabeledContent(L("状态"), value: account.availabilitySummary())
                    TextField(L("备注"), text: Binding(get: { model.preferences.notes[account.id] ?? "" }, set: { model.preferences.notes[account.id] = $0 }))
                    HStack {
                        Button(L("查看额度")) { model.onViewAccount?(account.id) }
                        if model.preferences.allowSwitching, account.id != model.identity.configuredAccountID {
                            Button(L("切换登录")) { model.requestSwitch(account.id) }
                                .disabled(model.preferences.demo || model.busy)
                        }
                        Spacer()
                        Button(L("移除账号"), role: .destructive) { pending = account; showRemove = true }
                            .disabled(model.preferences.demo || model.busy)
                    }
                }
            }
            if model.accounts.isEmpty {
                ContentUnavailableView(L("尚无账号"), systemImage: "person.crop.circle", description: Text(L("使用右上角按钮添加账号")))
            }
            if let message = model.message { Section { Text(message).foregroundStyle(.secondary) } }
        }.formStyle(.grouped).toggleStyle(.switch)
    }

    private var notifications: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("系统通知"))
                        Text(notificationDescription)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button(model.notificationAuthorization == .notDetermined ? L("允许通知") : L("打开设置")) {
                        if model.notificationAuthorization == .notDetermined { model.requestNotifications() }
                        else { model.openNotificationSettings() }
                    }.disabled(model.notificationAuthorization == nil || model.preferences.demo)
                }
            }
            Section(L("提醒事项")) {
                Toggle(L("额度偏低"), isOn: $model.preferences.notifyQuota)
                Toggle(L("其他账号恢复可用"), isOn: $model.preferences.notifyBackup)
                Toggle(isOn: $model.preferences.notifyTasks) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("等待授权、失败及本轮结束"))
                        Text(L("需先连接下方的任务事件。"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section(L("任务提醒")) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(L("任务事件"))
                            Text(taskConnectionStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        settingDescription(L("接收等待授权、本轮结束等事件，用于任务提醒。"))
                    }
                    Spacer(minLength: 8)
                    Button(model.hooksInstalled ? L("断开连接") : L("连接")) { model.toggleHooks(!model.hooksInstalled) }
                        .disabled(model.preferences.demo)
                }
            }
        }.formStyle(.grouped).toggleStyle(.switch)
            .task { await model.refreshNotificationAuthorization() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await model.refreshNotificationAuthorization() }
            }
    }

    private var notificationDescription: String {
        switch model.notificationAuthorization {
        case .authorized, .provisional, .ephemeral:
            return L("已允许系统通知，可在下方选择提醒事项。")
        case .denied:
            return L("系统通知已关闭，请在系统设置中允许 Codex Eyes 发送通知。")
        case .notDetermined:
            return L("允许 Codex Eyes 发送额度和任务提醒。")
        default:
            return L("正在读取系统通知设置。")
        }
    }

    private var taskConnectionStatus: String {
        if !model.hooksInstalled { return L("未连接") }
        return model.hooksReceived ? L("已收到任务事件") : L("尚未收到事件")
    }
    private func settingDescription(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

}

/// The user signs in using their existing client; this sheet never launches a login command.
private struct AddAccountView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var initialIDs: Set<String> = []

    private var addedAccount: Account? {
        model.orderedAccounts.first { !initialIDs.contains($0.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(L("添加账号"), systemImage: "person.badge.plus").font(.title2.weight(.semibold))
            Text(L("在 ChatGPT 的 Codex 中或 Codex 客户端正常登录账号。登录信息更新后，Codex Eyes 会自动识别并加入列表。"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let account = addedAccount {
                Label(L("已添加 ") + model.name(account), systemImage: "checkmark.circle.fill")
            } else {
                Label(L("等待本机 Codex 登录信息更新"), systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button(L("关闭")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 420)
        .onAppear {
            initialIDs = Set(model.accounts.map(\.id))
            Task { await model.syncConfiguredLoginIfChanged() }
        }
    }
}
