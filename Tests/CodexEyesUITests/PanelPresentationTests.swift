import AppKit
import XCTest
@testable import CodexEyes

final class PanelPresentationTests: XCTestCase {
    @MainActor func testStatusClickCannotDismissBeforeToggleAndHighlightTracksVisibility() async throws {
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: 26)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let panel = EyesPanel(contentRect: NSRect(x: 100, y: 100, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let presentation = PanelPresentation(panel: panel, button: button)
        let target = ToggleTarget(presentation)
        button.target = target
        button.action = #selector(ToggleTarget.toggle)
        button.performClick(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(button.state, .on)
        XCTAssertTrue(button.isHighlighted)
        let window = try XCTUnwrap(button.window)
        let bounds = window.convertToScreen(button.convert(button.bounds, to: nil))
        let click = NSPoint(x: bounds.midX, y: bounds.midY)
        // A global mouse monitor must leave status-item clicks for the toggle action.
        XCTAssertFalse(presentation.shouldDismiss(at: click, pinned: false, trackingMenu: false))
        button.performClick(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(button.state, .off)
        XCTAssertFalse(button.isHighlighted)
        button.performClick(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(button.state, .on)
        let outside = NSPoint(x: bounds.minX - 50, y: bounds.minY - 50)
        XCTAssertTrue(presentation.shouldDismiss(at: outside, pinned: false, trackingMenu: false))
        XCTAssertFalse(presentation.shouldDismiss(at: outside, pinned: true, trackingMenu: false))
        XCTAssertFalse(presentation.shouldDismiss(at: outside, pinned: false, trackingMenu: true))
        presentation.hide()
    }
}

@MainActor private final class ToggleTarget: NSObject {
    let presentation: PanelPresentation
    init(_ presentation: PanelPresentation) { self.presentation = presentation }
    @objc func toggle() {
        if presentation.panel.isVisible { presentation.hide() } else { presentation.show() }
    }
}
