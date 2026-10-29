import AppKit
import SwiftUI
import CodexEyesCore

enum PanelLayout {
    static let size = NSSize(width: 420, height: 700)
    static let bleed: CGFloat = 8
    static var windowSize: NSSize { NSSize(width: size.width + bleed * 2, height: size.height + bleed * 2) }
}

/// One system Liquid Glass surface; the content carries no simulated glass backgrounds.
@MainActor func nativeDashboard(model: AppModel, appearance: NSAppearance? = nil) -> NSView {
    let frame = NSRect(origin: NSPoint(x: PanelLayout.bleed, y: PanelLayout.bleed), size: PanelLayout.size)
    let container = ClearPanelContainer(frame: NSRect(origin: .zero, size: PanelLayout.windowSize))
    let currentAppearance = appearance ?? NSApp.effectiveAppearance
    let scheme: ColorScheme = currentAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    let content = TransparentHostingView(rootView: AnyView(AppPresentation(model: model, content: DashboardView(model: model).environment(\.colorScheme, scheme))))
    content.model = model
    content.colorAppearance = appearance
    content.appearance = appearance
    content.frame = NSRect(origin: .zero, size: PanelLayout.size)
    content.autoresizingMask = [.width, .height]
    let fittedHeight = max(250, ceil(content.fittingSize.height))
    let fittedSize = NSSize(width: PanelLayout.size.width, height: fittedHeight)
    content.setFrameSize(fittedSize)
    container.setFrameSize(NSSize(width: fittedSize.width + PanelLayout.bleed * 2, height: fittedHeight + PanelLayout.bleed * 2))
    let fittedFrame = NSRect(origin: frame.origin, size: fittedSize)

    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView(frame: fittedFrame)
        glass.autoresizingMask = [.width, .height]
        glass.style = .regular
        glass.cornerRadius = 22
        glass.appearance = appearance
        glass.contentView = content
        container.addSubview(glass)
        return container
    }

    let fallback = NSVisualEffectView(frame: fittedFrame)
    fallback.autoresizingMask = [.width, .height]
    fallback.material = .popover
    fallback.blendingMode = .behindWindow
    fallback.state = .active
    fallback.appearance = appearance
    fallback.wantsLayer = true
    fallback.layer?.cornerRadius = 18
    fallback.layer?.masksToBounds = true
    fallback.addSubview(content)
    container.addSubview(fallback)
    return container
}

@MainActor enum MenuBarQuotaImage {
    static func make(account: Account?) -> NSImage {
        let title = MenuBarQuota.title(for: account)
        let fraction = title == "—" ? nil : MenuBarQuota.window(for: account).map { $0.remaining / 100 }
        let number = title.replacingOccurrences(of: "%", with: "")
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let track = NSBezierPath(ovalIn: NSRect(x: 1.3, y: 1.3, width: 15.4, height: 15.4))
            track.lineWidth = 1.5
            NSColor.black.withAlphaComponent(0.23).setStroke(); track.stroke()
            if let fraction, fraction > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 7.7,
                              startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineWidth = 1.5; arc.lineCapStyle = .round
                NSColor.black.setStroke(); arc.stroke()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 7.2, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            let text = number as NSString; let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (18 - size.width) / 2, y: (18 - size.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = MenuBarQuota.summary(for: account)
        return image
    }
}

private final class ClearPanelContainer: NSView {
    override var isOpaque: Bool { false }
}

private final class TransparentHostingView: NSHostingView<AnyView> {
    var model: AppModel?
    var colorAppearance: NSAppearance?
    override var isOpaque: Bool { false }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard let model else { return }
        let scheme: ColorScheme = (colorAppearance ?? NSApp.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        rootView = AnyView(AppPresentation(model: model, content: DashboardView(model: model).environment(\.colorScheme, scheme)))
    }
}


/// Give AppKit concrete tooltip rectangles, including whitespace around chart marks.
/// SwiftUI's help regions on transparent stacks can shrink to their drawn children.
struct ChartToolTipRegion: Equatable {
    var rect: CGRect
    var text: String
}

struct ChartToolTips: NSViewRepresentable {
    var regions: [ChartToolTipRegion]
    func makeNSView(context: Context) -> ChartToolTipView { ChartToolTipView() }
    func updateNSView(_ view: ChartToolTipView, context: Context) { view.update(regions) }
}

final class ChartToolTipView: NSView {
    private var regions: [ChartToolTipRegion] = []
    private var labels: [NSView.ToolTipTag: String] = [:]
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    func update(_ regions: [ChartToolTipRegion]) {
        guard self.regions != regions else { return }
        self.regions = regions
        removeAllToolTips(); labels.removeAll()
        for region in regions {
            let tag = addToolTip(region.rect, owner: self, userData: nil)
            labels[tag] = region.text
        }
    }
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        labels[tag] ?? ""
    }
}
