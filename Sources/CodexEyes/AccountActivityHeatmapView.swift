import SwiftUI
import CodexEyesCore

struct AccountActivityHeatmapView: View {
    private let history: AccountActivityHeatmap
    @Environment(\.colorScheme) private var scheme
    @State private var hovered: AccountHeatmapLayout.CellIndex?
    @State private var contentOrigin = CGPoint.zero
    @State private var width: CGFloat = 540
    init(days: [AccountActivityDay]) {
        let actual = AccountActivityHeatmap(days: days)
        // Give short histories a little breathing room, with at most six extra weeks.
        history = AccountActivityHeatmap(days: days, contextWeeks: max(0, 16 - actual.weeks.count))
    }
    private var layout: AccountHeatmapLayout { .init(columns: history.weeks.count, availableWidth: width) }

    var body: some View {
        GeometryReader { geometry in
            let labels = monthLabels
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: layout.gap) {
                        ForEach(Array(history.weeks.enumerated()), id: \.element.id) { column, week in
                            VStack(spacing: 0) {
                                VStack(spacing: layout.gap) {
                                    ForEach(0..<7, id: \.self) { row in
                                        if let day = week.days[row] {
                                            RoundedRectangle(cornerRadius: min(3, layout.side / 4))
                                                .fill(color(day))
                                                .frame(width: layout.side, height: layout.side)
                                                .accessibilityLabel(day.date + " · " + amount(day, compact: false))
                                        } else {
                                            RoundedRectangle(cornerRadius: min(3, layout.side / 4))
                                                .fill(.primary.opacity(scheme == .dark ? 0.035 : 0.025))
                                                .frame(width: layout.side, height: layout.side)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                }
                                Color.clear.frame(width: layout.side, height: 26)
                                    .overlay(alignment: .bottomLeading) {
                                        if let label = labels[column] {
                                            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                                                .offset(x: min(0, layout.width - CGFloat(column) * layout.pitch -
                                                               (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width))
                                        }
                                    }
                            }.id(week.id)
                        }
                    }
                    .frame(width: layout.width, height: layout.height, alignment: .topLeading)
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(key: AccountHeatmapOrigin.self,
                                                   value: content.frame(in: .named("account-heatmap")).origin)
                        }
                    }
                    .overlay {
                        AccountHeatmapPointer { point in
                            let next = point.flatMap { layout.cell(at: $0) }.flatMap { index -> AccountHeatmapLayout.CellIndex? in
                                guard history.weeks.indices.contains(index.column), history.weeks[index.column].days[index.row] != nil else { return nil }
                                return index
                            }
                            if hovered != next { hovered = next }
                        }.frame(width: layout.width, height: layout.height)
                    }
                    .frame(minWidth: geometry.size.width, alignment: .center)
                }
                .onAppear { if let last = history.weeks.last { proxy.scrollTo(last.id, anchor: .trailing) } }
            }
            .overlay(alignment: .topLeading) {
                if let index = hovered, history.weeks.indices.contains(index.column), let day = history.weeks[index.column].days[index.row] {
                    let cell = layout.rect(column: index.column, row: index.row).offsetBy(dx: contentOrigin.x, dy: contentOrigin.y)
                    let bubbleSize = tooltipSize(day)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dateLabel(day)).font(.system(size: 11, weight: .medium))
                        Text(amount(day, compact: true)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10).frame(width: bubbleSize.width, height: bubbleSize.height, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                    .position(x: min(max(bubbleSize.width / 2, cell.midX), geometry.size.width - bubbleSize.width / 2),
                              y: cell.minY - bubbleSize.height / 2 - 6)
                    .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(AccountHeatmapOrigin.self) { origin in
                if contentOrigin != origin { contentOrigin = origin; hovered = nil }
            }
            .onAppear { width = geometry.size.width }
            .onChange(of: geometry.size.width) { _, value in width = value; hovered = nil }
        }
        .coordinateSpace(name: "account-heatmap")
        .frame(height: layout.height + 4).padding(.horizontal, 10).padding(.top, 10)
        .zIndex(1)
    }

    private func color(_ day: AccountActivityHeatmap.Day) -> Color {
        let level = history.level(for: day)
        if level == 0 { return .primary.opacity(scheme == .dark ? 0.07 : 0.055) }
        let dark = [Color(red: 0.08, green: 0.22, blue: 0.34), Color(red: 0.07, green: 0.35, blue: 0.57),
                    Color(red: 0.04, green: 0.53, blue: 0.91), Color(red: 0.44, green: 0.73, blue: 1)]
        let light = [Color(red: 0.75, green: 0.87, blue: 0.99), Color(red: 0.42, green: 0.70, blue: 0.99),
                     Color(red: 0.09, green: 0.55, blue: 0.99), Color(red: 0, green: 0.34, blue: 0.72)]
        return (scheme == .dark ? dark : light)[level - 1]
    }
    private var monthLabels: [Int: String] {
        var result: [Int: String] = [:]
        var previousEnd: CGFloat = -.infinity
        for column in history.weeks.indices {
            let days = history.weeks[column].days.compactMap { $0 }
            guard let day = column == 0 ? days.first : days.first(where: { $0.date.hasSuffix("-01") }) else { continue }
            let label: String
            if column == 0 { label = String(day.date.prefix(7)).replacingOccurrences(of: "-", with: "/") }
            else if day.date.hasSuffix("-01-01") { label = String(day.date.prefix(4)) }
            else {
                var format = Date.FormatStyle.dateTime.month(.abbreviated).locale(L10n.locale)
                format.timeZone = TimeZone(secondsFromGMT: 0)!
                label = day.calendarDate.formatted(format)
            }
            let labelWidth = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width
            let x = min(CGFloat(column) * layout.pitch, max(0, layout.width - labelWidth))
            guard x >= previousEnd + 12 else { continue }
            result[column] = label
            previousEnd = x + labelWidth
        }
        return result
    }
    private func dateLabel(_ day: AccountActivityHeatmap.Day) -> String {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day().locale(L10n.locale)
        format.timeZone = TimeZone(secondsFromGMT: 0)!
        return day.calendarDate.formatted(format)
    }
    private func tooltipSize(_ day: AccountActivityHeatmap.Day) -> CGSize {
        let dateWidth = (dateLabel(day) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width
        let valueWidth = (amount(day, compact: true) as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)]).width
        return CGSize(width: max(90, max(dateWidth, valueWidth) + 24), height: 48)
    }
    private func amount(_ day: AccountActivityHeatmap.Day, compact: Bool) -> String {
        day.tokens.map { (compact ? compactNumber($0) : $0.formatted()) + " Token" } ?? L("未提供记录")
    }
}

private struct AccountHeatmapOrigin: PreferenceKey {
    static var defaultValue = CGPoint.zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// Explicit tracking uses the same top-left origin as the grid, including scrolled content.
private struct AccountHeatmapPointer: NSViewRepresentable {
    var moved: (CGPoint?) -> Void
    func makeNSView(context: Context) -> AccountHeatmapPointerView { AccountHeatmapPointerView() }
    func updateNSView(_ view: AccountHeatmapPointerView, context: Context) { view.moved = moved }
}

private final class AccountHeatmapPointerView: NSView {
    var moved: ((CGPoint?) -> Void)?
    private var tracking: NSTrackingArea?
    private var monitor: Any?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard let window else { moved?(nil); return }
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window == self.window {
                let point = self.convert(event.locationInWindow, from: nil)
                self.moved?(self.visibleRect.contains(point) ? point : nil)
            } else { self.moved?(nil) }
            return event
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseDragged(with event: NSEvent) { track(event) }
    override func mouseDown(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) { moved?(nil) }
    override func scrollWheel(with event: NSEvent) { moved?(nil); super.scrollWheel(with: event) }
    private func track(_ event: NSEvent) { moved?(convert(event.locationInWindow, from: nil)) }
}
