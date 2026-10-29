import AppKit
import SwiftUI

/// Native popup menu and circular system bezel, alongside the selected value.
struct SettingsPicker<Value: Hashable>: NSViewRepresentable {
    var title: String
    @Binding var selection: Value
    var options: [(Value, String)]

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SettingsPickerControl {
        let control = SettingsPickerControl()
        control.popup.target = context.coordinator
        control.popup.action = #selector(Coordinator.changed(_:))
        return control
    }
    func updateNSView(_ control: SettingsPickerControl, context: Context) {
        context.coordinator.parent = self
        let titles = options.map(\.1)
        if control.popup.itemTitles != titles {
            control.popup.removeAllItems(); control.popup.addItems(withTitles: titles)
        }
        let index = options.firstIndex { $0.0 == selection } ?? 0
        control.popup.selectItem(at: index)
        control.label.stringValue = options.indices.contains(index) ? options[index].1 : ""
        control.popup.setAccessibilityLabel(title)
        control.popup.setAccessibilityValue(control.label.stringValue)
        control.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsPickerControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
    final class Coordinator: NSObject {
        var parent: SettingsPicker
        init(_ parent: SettingsPicker) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            guard parent.options.indices.contains(sender.indexOfSelectedItem) else { return }
            parent.selection = parent.options[sender.indexOfSelectedItem].0
        }
    }
}

final class SettingsPickerControl: NSView {
    fileprivate let label = PickerValueLabel(labelWithString: "")
    let popup = SettingsPopUpButton(frame: .zero, pullsDown: false)
    override var intrinsicContentSize: NSSize {
        NSSize(width: label.intrinsicContentSize.width + 28, height: 22)
    }
    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.setAccessibilityElement(false)
        popup.bezelStyle = .circular
        popup.isBordered = false
        popup.wantsLayer = true; popup.layer?.cornerRadius = 10
        updateIndicatorBackground()
        popup.imagePosition = .imageOnly
        let cell = popup.cell as! NSPopUpButtonCell
        cell.usesItemFromMenu = false; cell.arrowPosition = .noArrow
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        cell.menuItem = item
        for view in [label, popup] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            popup.trailingAnchor.constraint(equalTo: trailingAnchor),
            popup.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.widthAnchor.constraint(equalToConstant: 20), popup.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); updateIndicatorBackground()
    }
    private func updateIndicatorBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            popup.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
    }
    override func mouseDown(with event: NSEvent) { popup.performClick(nil) }
}

private final class PickerValueLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class SettingsPopUpButton: NSPopUpButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
}
