import AppKit
import SwiftUI
import CodexEyesCore

/// Native menu tracking and selection, with availability icons and a trailing login mark.
@MainActor struct LoginAccountMenu: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> SettingsPopUpButton {
        let button = SettingsPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .medium)
        let cell = button.cell as! NSPopUpButtonCell
        cell.usesItemFromMenu = false
        cell.altersStateOfSelectedItem = false
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.showsStateColumn = false
        menu.delegate = context.coordinator
        button.menu = menu
        context.coordinator.menuNeedsUpdate(menu)
        return button
    }
    func updateNSView(_ button: SettingsPopUpButton, context: Context) {
        context.coordinator.model = model
        let title = NSMutableAttributedString(string: L("当前登录") + " · ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor
        ])
        title.append(NSAttributedString(string: model.configuredName, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor
        ]))
        let display = NSMenuItem(title: model.configuredName, action: nil, keyEquivalent: "")
        display.attributedTitle = title
        (button.cell as! NSPopUpButtonCell).menuItem = display
        button.setAccessibilityLabel(L("切换登录账号"))
        button.setAccessibilityValue(model.configuredName)
        button.toolTip = L("当前登录配置") + " · " + model.configuredName
        button.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsPopUpButton, context: Context) -> CGSize? {
        CGSize(width: min(270, nsView.intrinsicContentSize.width), height: 26)
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var model: AppModel
        init(model: AppModel) { self.model = model }
        func menuNeedsUpdate(_ menu: NSMenu) {
            // Build only when opening. Token updates must not rebuild a menu while it is being tracked.
            menu.removeAllItems()
            // Pull-down buttons reserve their first item for the closed button title.
            let placeholder = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            placeholder.isHidden = true
            menu.addItem(placeholder)
            let accounts = model.orderedAccounts
            let names = accounts.map { String(model.name($0).prefix(36)) }
            let font = NSFont.menuFont(ofSize: 0)
            let titleWidth = max(150, names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 30
            for (account, name) in zip(accounts, names) {
                let current = account.id == model.identity.configuredAccountID
                let item = NSMenuItem(title: model.name(account), action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = account.id
                item.isEnabled = current || (model.preferences.allowSwitching && !model.busy && !model.preferences.demo)
                let paragraph = NSMutableParagraphStyle()
                paragraph.tabStops = [NSTextTab(textAlignment: .right, location: titleWidth)]
                item.attributedTitle = NSAttributedString(string: name + "\t" + (current ? "✓" : "\u{200B}"),
                                                          attributes: [.font: font, .paragraphStyle: paragraph])
                let color = NSColor(EyesTheme.status(account.availability()))
                item.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { _ in
                    color.setFill()
                    NSBezierPath(ovalIn: NSRect(x: 3.5, y: 3.5, width: 5, height: 5)).fill()
                    return true
                }
                // Public macOS 27 property, resolved dynamically so Xcode 26 can still build the app.
                if #available(macOS 27.0, *), item.responds(to: NSSelectorFromString("setPreferredImageVisibility:")) {
                    item.setValue(1, forKey: "preferredImageVisibility") // NSMenuItemImageVisibilityVisible
                }
                item.toolTip = model.name(account) + " · " + account.availabilitySummary()
                item.setAccessibilityLabel(model.name(account) + " · " + account.availabilitySummary() + (current ? " · " + L("当前登录") : ""))
                menu.addItem(item)
            }
            if accounts.isEmpty || !model.preferences.allowSwitching {
                if !accounts.isEmpty { menu.addItem(.separator()) }
                let item = NSMenuItem(title: L("在设置中允许切换登录"), action: #selector(settings), keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
        }
        @objc private func choose(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String, id != model.identity.configuredAccountID else { return }
            model.requestSwitch(id)
        }
        @objc private func settings() { model.onSettings?() }
    }
}
