import AppKit

/// Keep the status item's native highlight and the panel's visibility in sync.
@MainActor final class PanelPresentation {
    let panel: NSPanel
    let button: NSStatusBarButton

    init(panel: NSPanel, button: NSStatusBarButton) {
        self.panel = panel
        self.button = button
        (button.cell as? NSButtonCell)?.showsStateBy = .changeBackgroundCellMask
        button.sendAction(on: .leftMouseUp)
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        button.state = .on
        updateHighlight()
    }

    func hide() {
        panel.orderOut(nil)
        button.state = .off
        updateHighlight()
    }

    private func updateHighlight() {
        button.highlight(panel.isVisible)
        // NSButton clears its pressed highlight after the action finishes tracking.
        // Restore the panel's actual state on the next main-loop pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.button.highlight(self.panel.isVisible)
        }
    }

    func isStatusButtonClick(at screenPoint: NSPoint) -> Bool {
        guard let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(screenPoint)
    }

    func shouldDismiss(at screenPoint: NSPoint, pinned: Bool, trackingMenu: Bool) -> Bool {
        panel.isVisible && !pinned && !trackingMenu && panel.attachedSheet == nil
            && !isStatusButtonClick(at: screenPoint)
    }
}
