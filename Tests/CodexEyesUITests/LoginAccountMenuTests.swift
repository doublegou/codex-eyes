import AppKit
import SwiftUI
import XCTest
import CodexEyesCore
@testable import CodexEyes

final class LoginAccountMenuTests: XCTestCase {
    @MainActor func testTitleTracksConfiguredAccountWithoutRecreatingView() async throws {
        _ = NSApplication.shared
        let model = AppModel(demo: true, previewLanguage: .simplifiedChinese)
        model.preferences.notes = [:]
        model.preferences.privacy = false
        let accounts = DemoData.accounts().accounts
        let first = accounts[0], second = accounts[1]
        model.accounts = accounts
        model.identity.reconcile(AccountList(activeAccountKey: first.id, accounts: accounts))

        let host = NSHostingView(rootView: LoginAccountMenu(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 50),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(findButton(in: host))
        await settle(host)
        XCTAssertEqual(button.accessibilityValue() as? String, first.displayName)

        // This is the same identity update used after a verified switch or external login.
        // Keep viewing the old account to catch accidental coupling to the viewed identity.
        model.identity.reconcile(AccountList(activeAccountKey: second.id, accounts: accounts))
        await settle(host)
        XCTAssertEqual(model.identity.viewedAccountID, first.id)
        XCTAssertEqual(button.accessibilityValue() as? String, second.displayName)
        XCTAssertEqual((button.cell as? NSPopUpButtonCell)?.menuItem?.attributedTitle?.string,
                       "当前登录 · " + second.displayName)

        let menu = try XCTUnwrap(button.menu)
        menu.delegate?.menuNeedsUpdate?(menu)
        XCTAssertTrue(menu.items.first { $0.representedObject as? String == second.id }?
            .attributedTitle?.string.hasSuffix("✓") == true)

        model.preferences.notes[second.id] = "Renamed account"
        await settle(host)
        XCTAssertEqual(button.accessibilityValue() as? String, "Renamed account")

        model.identity.reconcile(AccountList(activeAccountKey: first.id, accounts: accounts))
        await settle(host)
        XCTAssertEqual(button.accessibilityValue() as? String, first.displayName)
        XCTAssertTrue(findButton(in: host) === button)
    }

    @MainActor private func settle(_ host: NSView) async {
        // Let SwiftUI deliver ObservableObject changes to the existing AppKit control.
        try? await Task.sleep(nanoseconds: 100_000_000)
        host.layoutSubtreeIfNeeded()
    }

    @MainActor private func findButton(in view: NSView) -> NSPopUpButton? {
        if let button = view as? NSPopUpButton { return button }
        return view.subviews.lazy.compactMap { self.findButton(in: $0) }.first
    }
}
