import AppKit
import SwiftUI
import Carbon
import CodexEyesCore

struct ShortcutSetting: View {
    @ObservedObject var model: AppModel
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L("展开看板"))
                Spacer()
                ShortcutRecorder(shortcut: model.preferences.shortcut,
                                 onChange: { error = model.updateShortcut($0) },
                                 onRecording: { model.onShortcutRecording?($0) })
                    .frame(width: 128, height: 25)
                Button { error = model.updateShortcut(.standard) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }.buttonStyle(.borderless).help(L("恢复默认快捷键"))
                    .disabled(model.preferences.shortcut == .standard)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: PanelShortcut
    var onChange: (PanelShortcut) -> Void
    var onRecording: (Bool) -> Void
    func makeNSView(context: Context) -> ShortcutButton { ShortcutButton() }
    func updateNSView(_ view: ShortcutButton, context: Context) {
        view.shortcut = shortcut; view.onChange = onChange; view.onRecording = onRecording
        if !view.recording { view.title = shortcut.display }
        view.toolTip = L("点击后按下新的快捷键，按 Esc 取消")
        view.setAccessibilityLabel(L("展开看板快捷键"))
    }
    static func dismantleNSView(_ view: ShortcutButton, coordinator: ()) { view.stopRecording() }
}

private final class ShortcutButton: NSButton {
    var shortcut = PanelShortcut.standard
    var onChange: ((PanelShortcut) -> Void)?
    var onRecording: ((Bool) -> Void)?
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded; setButtonType(.momentaryPushIn)
        font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        target = self; action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func beginRecording() {
        guard window?.makeFirstResponder(self) == true else { return }
        recording = true; title = L("按下快捷键"); onRecording?(true)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(stopRecording),
                                                   name: NSWindow.didResignKeyNotification, object: window)
        } else { stopRecording() }
    }
    @objc func stopRecording() {
        guard recording else { return }
        recording = false; title = shortcut.display; onRecording?(false)
    }
    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 || event.keyCode == 48 {
            stopRecording()
            window?.makeFirstResponder(nil); return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        let candidate = PanelShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                                      key: (event.charactersIgnoringModifiers ?? "").uppercased())
        onChange?(candidate)
        stopRecording()
        window?.makeFirstResponder(nil)
    }
}
