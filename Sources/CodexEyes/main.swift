import AppKit
import SwiftUI
import Carbon
import Combine
import CodexEyesCore

@MainActor final class EyesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: AppModel
    private var statusItem: NSStatusItem!
    private var panel: EyesPanel!
    private var settings: NSWindow?
    private var usageDetails: NSWindow?
    private var switchingLogin = false
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var menuTrackingDepth = 0
    private var menuObservers: [NSObjectProtocol] = []
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var statusSubscription: AnyCancellable?
    private var presentationSubscription: AnyCancellable?
    init(demo: Bool) { model = AppModel(demo: demo); super.init() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyAppearance()
        statusItem = NSStatusBar.system.statusItem(withLength: 26)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(toggle)
            button.imagePosition = .imageOnly
        }
        statusSubscription = Publishers.CombineLatest3(model.$accounts, model.$identity, model.$preferences)
            .receive(on: RunLoop.main)
            .sink { [weak self] accounts, identity, preferences in
                guard let self else { return }
                let configured = accounts.first { $0.id == identity.configuredAccountID }
                self.statusItem.button?.image = MenuBarQuotaImage.make(account: configured)
                self.statusItem.button?.title = ""
                let prefix = preferences.demo ? "Codex Eyes Preview\n" : ((preferences.privacy ? nil : configured?.displayName) ?? "Codex Eyes") + "\n"
                self.statusItem.button?.toolTip = prefix + MenuBarQuota.summary(for: configured)
                self.statusItem.button?.setAccessibilityLabel(prefix + MenuBarQuota.summary(for: configured))
            }
        panel = EyesPanel(contentRect: NSRect(origin: .zero, size: PanelLayout.windowSize),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Codex Eyes"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.delegate = self
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        model.onPanelHeight = { [weak self] height in
            Task { @MainActor in self?.fitPanel(height: height) }
        }
        panel.contentView = nativeDashboard(model: model)
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onRequestSwitch = { [weak self] id in self?.requestLoginSwitch(id) }
        model.onDetails = { [weak self] in self?.showUsageDetails() }
        model.onViewAccount = { [weak self] id in
            guard let self else { return }
            self.settings?.orderOut(nil); self.show(); self.model.view(id)
        }
        model.onPin = { [weak self] in
            guard let self else { return }
            self.model.pinned.toggle()
        }
        model.onQuit = { NSApp.terminate(nil) }
        model.pinned = CommandLine.arguments.contains("--pin")
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingDepth += 1 }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                // Finish processing the menu's selection event before enabling outside-click dismissal.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
                }
            }
        ]
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in if let self, !self.model.pinned, self.panel.attachedSheet == nil { self.hide() } }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if self.panel.attachedSheet != nil || self.menuTrackingDepth > 0 { return event }
            // Native menu clicks are not clicks outside the dashboard.
            if event.type != .keyDown, event.window == nil || event.window?.level == .popUpMenu { return event }
            if event.type == .keyDown && event.keyCode == 53 && event.window == self.panel { self.hide(); return nil }
            if event.type != .keyDown, event.window != self.panel, event.window != self.statusItem.button?.window, !self.model.pinned { self.hide() }
            return event
        }
        model.onShortcutChange = { [weak self] shortcut in self?.registerHotKey(shortcut) }
        model.onShortcutRecording = { [weak self] recording in
            guard let self else { return }
            if recording {
                if let key = self.hotKey { UnregisterEventHotKey(key); self.hotKey = nil }
            } else if self.hotKey == nil, let error = self.registerHotKey(self.model.preferences.shortcut) {
                self.model.message = error
            }
        }
        if let error = registerHotKey(model.preferences.shortcut) { model.message = error }
        presentationSubscription = model.$preferences.map(\.appearance).removeDuplicates()
            .dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.applyAppearance()
        }
        model.start()
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched.v1")
        UserDefaults.standard.set(true, forKey: "hasLaunched.v1")
        if CommandLine.arguments.contains("--settings") { showSettings() }
        else if firstLaunch || CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--demo") { show() }
    }
    @objc func toggle() { panel.isVisible ? hide() : show() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }
    func show() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let buttonFrame = statusItem.button?.window?.frame ?? NSRect(x: frame.maxX - 340, y: frame.maxY, width: 31, height: 25)
        let x = min(max(frame.minX + 8, buttonFrame.midX - PanelLayout.windowSize.width / 2), frame.maxX - PanelLayout.windowSize.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: max(frame.minY + 8, frame.maxY - panel.frame.height + PanelLayout.bleed - 5)))
        model.opened(); panel.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func hide() { panel.orderOut(nil); model.panelVisible = false }
    func fitPanel(height: CGFloat) {
        guard let panel, height.isFinite else { return }
        let height = max(250, ceil(height)) + PanelLayout.bleed * 2
        guard abs(panel.frame.height - height) > 1 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height; frame.size.height = height
        panel.setFrame(frame, display: true)
    }
    func showUsageDetails() {
        if usageDetails == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = L("用量明细"); window.isReleasedWhenClosed = false
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = false
            window.minSize = NSSize(width: 700, height: 500)
            window.contentView = NSHostingView(rootView: AppPresentation(model: model, content: UsageDetailsView(model: model)))
            window.center(); usageDetails = window
        }
        hide()
        NSApp.activate(ignoringOtherApps: true); usageDetails?.makeKeyAndOrderFront(nil)
    }
    func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = L("Codex Eyes · 设置"); window.isReleasedWhenClosed = false
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = false
            window.minSize = NSSize(width: 680, height: 480)
            window.contentView = NSHostingView(rootView: AppPresentation(model: model, content: SettingsView(model: model))); window.center()
            settings = window
        }
        hide()
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    private func requestLoginSwitch(_ id: String, in parent: NSWindow? = nil) {
        guard !switchingLogin else { return }
        let window = parent ?? (settings?.isVisible == true && !panel.isVisible ? settings! : panel!)
        guard window.attachedSheet == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if window == panel { model.panelVisible = true }
        do {
            let needsConfirmation = try model.prepareLoginSwitch(id)
            guard let target = model.accounts.first(where: { $0.id == id }) else { return }
            if !needsConfirmation { switchLogin(id, in: window); return }
            let alert = NSAlert()
            alert.messageText = L("切换登录账号？")
            alert.informativeText = L("从 \(model.configuredName) 切换到 \(model.name(target))。下次启动 ChatGPT / Codex 时生效。")
            alert.addButton(withTitle: L("切换登录"))
            alert.addButton(withTitle: L("取消"))
            alert.showsSuppressionButton = true
            let suppression = alert.suppressionButton
            suppression?.title = L("不再提醒")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn else { return }
                self.model.preferences.skipSwitchConfirmation = suppression?.state == .on
                DispatchQueue.main.async { self.switchLogin(id, in: window) }
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("暂时无法切换登录")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L("重新检查"))
            alert.addButton(withTitle: L("取消"))
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    DispatchQueue.main.async { self?.requestLoginSwitch(id, in: window) }
                }
            }
        }
    }
    private func switchLogin(_ id: String, in window: NSWindow) {
        switchingLogin = true
        Task { @MainActor in
            let success = await model.perform("switch", id: id)
            switchingLogin = false
            let alert = NSAlert()
            alert.alertStyle = success ? .informational : .warning
            alert.messageText = success ? L("登录配置已切换") : L("未能切换登录")
            alert.informativeText = success ? L("下次启动 ChatGPT / Codex 时生效。") : (model.message ?? L("请刷新账号状态后重试。"))
            alert.addButton(withTitle: L("好"))
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }
    private func applyAppearance() {
        switch model.preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    private func registerHotKey(_ shortcut: PanelShortcut) -> String? {
        guard shortcut.isValid else { return L("无效的快捷键。") }
        if hotKeyHandler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
                guard let pointer else { return noErr }
                MainActor.assumeIsolated { Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue().toggle() }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        let id = EventHotKeyID(signature: 0x45594553, id: 1)
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr, let replacement else { return L("此快捷键无法使用，可能已被其他应用占用。请换一个组合。") }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        return nil
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
    }
}

@MainActor func renderPreview(to path: String, dark: Bool) {
    let model = AppModel(demo: true, previewLanguage: CommandLine.arguments.contains("--english") ? .english : .simplifiedChinese)
    model.panelVisible = false
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    NSApp.appearance = appearance
    let view: NSView
    if CommandLine.arguments.contains("--settings") {
        let tab = CommandLine.arguments.contains("--accounts") ? 1 : (CommandLine.arguments.contains("--notifications") ? 2 : 0)
        view = NSHostingView(rootView: SettingsView(model: model, initialTab: tab).environment(\.colorScheme, dark ? .dark : .light))
        view.frame = NSRect(x: 0, y: 0, width: 780, height: 580)
    } else if CommandLine.arguments.contains("--details") {
        view = NSHostingView(rootView: UsageDetailsView(model: model, initialTab: CommandLine.arguments.contains("--account-activity") ? 3 : (CommandLine.arguments.contains("--session") ? 1 : 0), initialHeatmap: CommandLine.arguments.contains("--heatmap")).environment(\.colorScheme, dark ? .dark : .light))
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    } else {
        view = nativeDashboard(model: model, appearance: appearance)
    }
    view.appearance = appearance
    let auxiliary = CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--details")
    let window = NSWindow(contentRect: view.frame, styleMask: auxiliary ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless], backing: .buffered, defer: false)
    if auxiliary { window.toolbarStyle = .unified; window.titlebarAppearsTransparent = true }
    window.appearance = appearance
    window.isOpaque = auxiliary
    window.backgroundColor = auxiliary ? .windowBackgroundColor : .clear
    window.contentView = view
    if auxiliary {
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
    view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    let capture = auxiliary ? (view.superview ?? view) : view
    guard let bitmap = capture.bitmapImageRepForCachingDisplay(in: capture.bounds) else { return }
    capture.cacheDisplay(in: capture.bounds, to: bitmap)
    if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.indices.contains(index + 1) {
        app.setActivationPolicy(.accessory)
        renderPreview(to: CommandLine.arguments[index + 1], dark: CommandLine.arguments.contains("--dark"))
    } else {
        let delegate = AppDelegate(demo: CommandLine.arguments.contains("--demo"))
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
